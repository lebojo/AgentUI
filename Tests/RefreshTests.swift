import Foundation

@MainActor enum RefreshTests {
    static func run(root: URL) async throws {
        let fm = FileManager.default
        let watched = root.appendingPathComponent("watched")
        try fm.createDirectory(at: watched, withIntermediateDirectories: true)
        let events = Counter()
        let watching = Task { for await _ in FileEvents.changes(in: [watched.path], latency: .milliseconds(50)) { await events.increment() } }
        try await wait(until: { await events.value == 1 }, "The first value is delivered immediately")
        try "change".write(to: watched.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await wait(until: { await events.value >= 2 }, "A file change is delivered by FSEvents")
        watching.cancel()
        await watching.value
        let ticks = Counter()
        let ticking = Task { for await _ in FileEvents.changes(in: [], latency: .milliseconds(50), every: .milliseconds(20)) { await ticks.increment() } }
        try await wait(until: { await ticks.value >= 3 }, "Periodic values are delivered without a watcher")
        ticking.cancel()
        await ticking.value
        print("PASS file events, periodic fallback and cancellation")

        let repository = root.appendingPathComponent("event-repo")
        try fm.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-b", "main"], at: repository.path)
        try "one\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "."], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "fixture"], at: repository.path)
        let reads = Counter()
        let model = InspectorStore(readLocal: { path in
            await reads.increment()
            return try await InspectorService.localGit(at: path)
        }, readRemote: { local in
            GitHubSnapshot(repository: GitHubRepository(nameWithOwner: "fixture/app", url: "https://github.com/fixture/app", description: nil),
                           pullRequest: nil, runs: [], pullRequestError: nil, checksError: nil)
        })
        let changes = await FileEvents.repositoryChanges(at: repository.path)
        let monitoring = Task { await model.monitor(path: repository.path, changes: changes) }
        try await wait(until: { model.local != nil }, "The inspector reads the repository on start")
        try await Task.sleep(for: .seconds(1.5))
        let settledReads = await reads.value
        try await Task.sleep(for: .seconds(2.5))
        let idleReads = await reads.value
        try CoreTests.require(settledReads <= 2 && idleReads == settledReads,
                              "Git reads do not trigger themselves through file events, got \(settledReads) then \(idleReads) reads")
        try "two\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try await wait(until: { model.local?.changes.map(\.path) == ["tracked.txt"] }, "Editing a file refreshes Git status")
        monitoring.cancel()
        await monitoring.value
        print("PASS event-driven inspector refresh without self-triggering")

        let listings = Counter()
        let guardian = GitFilterGuard { root in
            await listings.increment()
            return try await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/git"), GitConfiguration.listingArguments, at: root)
        }
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        _ = try await guardian.configuration(at: repository.path)
        let unchanged = await listings.value
        try CoreTests.require(unchanged == 1, "Unchanged configuration is not listed again")
        _ = try await GitService.run(["config", "filter.added.clean", "cat"], at: repository.path)
        let added = try await guardian.configuration(at: repository.path)
        let afterAdd = await listings.value
        try CoreTests.require(afterAdd == 2 && added["filter.added.clean"] == "", "A filter added to .git/config is disabled on the next read")
        _ = try await GitService.run(["config", "include.path", "../later.cfg"], at: repository.path)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        _ = try await guardian.configuration(at: repository.path)
        let beforeInclude = await listings.value
        try "[filter \"late\"]\n\tclean = cat\n".write(to: repository.appendingPathComponent("later.cfg"), atomically: true, encoding: .utf8)
        let included = try await guardian.configuration(at: repository.path)
        let afterInclude = await listings.value
        try CoreTests.require(afterInclude == beforeInclude + 1 && included["filter.late.clean"] == "",
                              "A filter defined by an include target created later is disabled")
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        let beforeSwitch = await listings.value
        _ = try await GitService.run(["switch", "-c", "other"], at: repository.path)
        _ = try await guardian.configuration(at: repository.path)
        let afterSwitch = await listings.value
        try CoreTests.require(afterSwitch == beforeSwitch + 1, "A branch change lists configuration again for onbranch includes")
        print("PASS git config is listed only when a configuration file, include target or HEAD changes")
    }

    private static func wait(until condition: () async -> Bool, _ message: String, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WorkspaceError(message: "FAIL: " + message)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
