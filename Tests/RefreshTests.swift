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
        let model = InspectorStore()
        let changes = await FileEvents.repositoryChanges(at: repository.path)
        let monitoring = Task {
            await model.monitor(path: repository.path, changes: changes, readLocal: { path in
                await reads.increment()
                return try await InspectorService.localGit(at: path)
            }, readRemote: { local in
                RemoteSnapshot(repository: RemoteRepository(nameWithOwner: "fixture/app", url: "https://github.com/fixture/app", description: nil),
                               changeRequest: nil, runs: [], changeRequestError: nil, checksError: nil)
            })
        }
        try await wait(until: { model.local != nil }, "The inspector reads the repository on start")
        try await Task.sleep(for: .seconds(1.5))
        let settledReads = await reads.value
        try await Task.sleep(for: .seconds(2.5))
        let idleReads = await reads.value
        try CoreTests.require(settledReads <= 2 && idleReads == settledReads,
                              "Git reads do not trigger themselves through file events, got \(settledReads) then \(idleReads) reads")
        try "two\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try await wait(until: { model.local?.changes.map(\.path) == ["tracked.txt"] }, "Editing a file refreshes Git status")
        try await wait(until: { model.lacksChangeRequest }, "A branch without a pull request offers the comparison")
        let firstHead = model.local?.headSHA
        _ = try await GitService.run(["-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "commit", "-qam", "second"], at: repository.path)
        try await wait(until: { model.local?.headSHA != firstHead }, "A commit refreshes HEAD")
        try CoreTests.require(model.lacksChangeRequest, "A new commit on the same branch keeps the comparison in place")
        try await Task.sleep(for: .seconds(1.5))
        let beforeAction = await reads.value
        let failed = await model.perform(.stageAll, at: repository.path) { _, _ in throw ReadCommandError(message: "boom") }
        try CoreTests.require(!failed && model.actionFailure == GitActionFailure(action: .stageAll, error: "boom") && model.pendingAction == nil,
                              "A failed Git action is reported inline with the action")
        try await wait(until: { await reads.value > beforeAction }, "A Git action reloads the status without waiting for file events")
        try "three\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let staged = await model.perform(.stageAll, at: repository.path) { try await InspectorService.perform($0, at: $1) }
        try CoreTests.require(staged && model.actionFailure == nil, "Retrying the failed Git action successfully clears its error")
        try await wait(until: { model.local?.stagedChanges.map(\.path) == ["tracked.txt"] }, "Staging refreshes the sections")
        monitoring.cancel()
        await monitoring.value
        print("PASS event-driven inspector refresh without self-triggering")

        let queue = InspectorStore()
        var performed: [String] = []
        let first = Task {
            await queue.perform(.stage(["a"]), at: repository.path) { action, _ in
                performed.append("start \(action.arguments.last ?? "")")
                try await Task.sleep(for: .milliseconds(200))
                performed.append("end \(action.arguments.last ?? "")")
                throw ReadCommandError(message: "first failed")
            }
        }
        try await wait(until: { queue.pendingAction == .stage(["a"]) }, "The first Git action starts")
        let second = Task {
            await queue.perform(.stage(["b"]), at: repository.path) { action, _ in performed.append("run \(action.arguments.last ?? "")") }
        }
        let third = Task {
            await queue.perform(.unstage(["c"]), at: repository.path) { action, _ in performed.append("run \(action.arguments.last ?? "")") }
        }
        let results = await [first.value, second.value, third.value]
        try CoreTests.require(performed == ["start a", "end a", "run b", "run c"] && results == [false, true, true]
                              && queue.pendingAction == nil && queue.actionFailure == GitActionFailure(action: .stage(["a"]), error: "first failed"),
                              "Git actions clicked while another runs are queued in order, and other successes keep the earlier failure")
        await queue.perform(.stage(["a"]), at: repository.path) { _, _ in }
        try CoreTests.require(queue.actionFailure == nil, "Staging the same file again successfully clears its failure")
        await queue.perform(.publish(remote: "origin", branch: "main"), at: repository.path) { _, _ in throw ReadCommandError(message: "denied") }
        await queue.perform(.commit(title: "t", message: ""), at: repository.path) { _, _ in }
        let pushFailure = queue.actionFailure
        await queue.perform(.push, at: repository.path) { _, _ in }
        try CoreTests.require(pushFailure?.action == .publish(remote: "origin", branch: "main") && queue.actionFailure == nil,
                              "A commit keeps a push failure and a later successful push clears it")
        print("PASS queued Git actions")

        let hanging = Task {
            await queue.perform(.commit(title: "t", message: ""), at: repository.path) { _, _ in
                _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["600"], at: repository.path, timeout: 3600, limit: 0, readOnly: false)
            }
        }
        try await wait(until: { queue.pendingAction == .commit(title: "t", message: "") }, "A hanging Git action starts")
        var pushed = false
        let queuedPush = Task {
            await queue.perform(.push, at: repository.path) { _, _ in pushed = true }
        }
        try await Task.sleep(for: .milliseconds(200))
        let cancelledAt = ContinuousClock.now
        queue.cancelActions()
        let hangingResult = await hanging.value
        let queuedPushResult = await queuedPush.value
        try CoreTests.require(!hangingResult && queue.pendingAction == nil && queue.actionFailure == nil && cancelledAt.duration(to: .now) < .seconds(5),
                              "Cancelling the running Git action stops its process without reporting a failure")
        try CoreTests.require(!queuedPushResult && !pushed && queue.actionFailure == nil, "Cancelling also drops the queued Git actions")
        let handingOff = GitActionQueue()
        var ranAfterHandOff = false
        let handedOff = Task {
            try? await Task.sleep(for: .milliseconds(50))
            return await handingOff.perform(.push) { ranAfterHandOff = true }
        }
        let finishedBeforeCancel = await handingOff.perform(.stageAll) { try await Task.sleep(for: .milliseconds(300)) }
        handingOff.cancel()
        let handedOffResult = await handedOff.value
        try CoreTests.require(finishedBeforeCancel && !handedOffResult && !ranAfterHandOff && handingOff.pendingAction == nil,
                              "Cancelling right after a Git action finishes drops the action it was handing over to")
        let afterHandOff = await handingOff.perform(.push) {}
        try CoreTests.require(afterHandOff, "A Git action clicked after a cancel still runs")
        print("PASS cancelled Git action")

        let sharedQueues = GitActionQueues()
        let leaving = InspectorStore(actionQueues: sharedQueues), returning = InspectorStore(actionQueues: sharedQueues)
        let elsewhere = InspectorStore(actionQueues: sharedQueues)
        let sharedRunning = Task {
            await leaving.perform(.stageAll, at: repository.path) { _, _ in try await Task.sleep(for: .seconds(600)) }
        }
        try await wait(until: { leaving.pendingAction == .stageAll }, "A Git action starts in the first inspector")
        leaving.commitTitle = "Draft"
        var ranConcurrently = false
        let sharedWaiting = Task {
            await returning.perform(.unstageAll, at: repository.path) { _, _ in ranConcurrently = true }
        }
        let otherRepository = await elsewhere.perform(.stageAll, at: root.path) { _, _ in }
        try await Task.sleep(for: .milliseconds(100))
        try CoreTests.require(returning.pendingAction == .stageAll && returning.commitTitle == "Draft" && !ranConcurrently && otherRepository,
                              "Inspectors of the same repository share its running Git action, queue and draft; other repositories run on their own")
        returning.cancelActions()
        let sharedResults = await [sharedRunning.value, sharedWaiting.value]
        try CoreTests.require(sharedResults == [false, false] && !ranConcurrently && leaving.pendingAction == nil,
                              "Cancelling from another inspector stops the shared action and its queue")
        print("PASS Git actions shared by repository")

        let pruned = GitActionQueues()
        let idle = pruned.queue(at: "/repo/gone"), drafted = pruned.queue(at: "/repo/drafted"), parent = pruned.queue(at: "/repo/parent")
        drafted.commitTitle = "Keep me"
        pruned.prune(keepingRootsOf: ["/repo/parent/sub"])
        try CoreTests.require(pruned.queue(at: "/repo/gone") !== idle && pruned.queue(at: "/repo/drafted") === drafted
                                && pruned.queue(at: "/repo/parent") === parent,
                              "Idle Git action queues of removed worktrees are dropped; drafts and repositories still in use are kept")

        let lock = repository.appendingPathComponent("index.lock")
        let cleanup = "touch index.lock; trap 'rm -f index.lock; exit 143' TERM; while true; do sleep 0.05; done"
        let locking = Task {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", cleanup], at: repository.path, timeout: 3600, limit: 0, readOnly: false)
        }
        try await wait(until: { FileManager.default.fileExists(atPath: lock.path) }, "A command creating a lock starts")
        locking.cancel()
        _ = await locking.result
        try CoreTests.require(!FileManager.default.fileExists(atPath: lock.path), "A cancelled command is asked to stop and removes its lock")
        let stubborn = Task {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "trap '' TERM; sleep 600"], at: repository.path,
                                            timeout: 3600, limit: 0, readOnly: false)
        }
        try await Task.sleep(for: .milliseconds(200))
        let stubbornCancelledAt = ContinuousClock.now
        stubborn.cancel()
        _ = await stubborn.result
        let stubbornDelay = stubbornCancelledAt.duration(to: .now)
        try CoreTests.require(stubbornDelay >= .seconds(1) && stubbornDelay < .seconds(5), "A command ignoring the stop request is killed after a grace period")
        let helperFile = repository.appendingPathComponent("helper.pid")
        let spawning = "(trap '' TERM; exec sleep 600) & echo $! > helper.pid; trap 'exit 143' TERM; while true; do sleep 0.05; done"
        let leader = Task {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", spawning], at: repository.path, timeout: 3600, limit: 0, readOnly: false)
        }
        try await wait(until: { ((try? String(contentsOf: helperFile, encoding: .utf8)) ?? "").hasSuffix("\n") }, "A command starts a helper ignoring TERM")
        let helper = try pid_t(String(contentsOf: helperFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        try CoreTests.require(helper > 0 && kill(helper, 0) == 0, "The helper runs in the command's process group")
        leader.cancel()
        _ = await leader.result
        try await wait(until: { kill(helper, 0) == -1 && errno == ESRCH }, "A stopped command takes down the helpers of its process group", timeout: .seconds(1))
        try? fm.removeItem(at: helperFile)
        print("PASS cancelled command cleanup")

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
        try CoreTests.require(afterAdd == 2 && added.overrides["filter.added.clean"] == "", "A filter added to .git/config is disabled on the next read")
        _ = try await GitService.run(["config", "include.path", "../later.cfg"], at: repository.path)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        _ = try await guardian.configuration(at: repository.path)
        let beforeInclude = await listings.value
        try "[filter \"late\"]\n\tclean = cat\n".write(to: repository.appendingPathComponent("later.cfg"), atomically: true, encoding: .utf8)
        let included = try await guardian.configuration(at: repository.path)
        let afterInclude = await listings.value
        try CoreTests.require(afterInclude == beforeInclude + 1 && included.overrides["filter.late.clean"] == "",
                              "A filter defined by an include target created later is disabled")
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        let beforeSwitch = await listings.value
        _ = try await GitService.run(["switch", "-c", "other"], at: repository.path)
        _ = try await guardian.configuration(at: repository.path)
        let afterSwitch = await listings.value
        try CoreTests.require(afterSwitch == beforeSwitch + 1, "A branch change lists configuration again for onbranch includes")
        print("PASS git config is listed only when a configuration file, include target or HEAD changes")

        try await Task.sleep(for: .milliseconds(20))
        let empty = try await guardian.configuration(at: repository.path).remotes
        let beforeRemote = await listings.value
        _ = try await GitService.run(["remote", "add", "origin", "git@github.com:fixture/app.git"], at: repository.path)
        let addedRemote = try await guardian.configuration(at: repository.path).remotes
        let afterRemote = await listings.value
        try CoreTests.require(empty.primaryURL == nil && addedRemote.primaryURL == "git@github.com:fixture/app.git" && afterRemote == beforeRemote + 1,
                              "A remote added to .git/config is read from the same single listing")
        _ = try await GitService.run(["config", "--add", "include.path", "../remotes.cfg"], at: repository.path)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await guardian.configuration(at: repository.path)
        try "[remote \"fork\"]\n\turl = git@github.com:me/app.git\n".write(to: repository.appendingPathComponent("remotes.cfg"), atomically: true, encoding: .utf8)
        let includedRemote = try await guardian.configuration(at: repository.path).remotes
        try CoreTests.require(includedRemote.remotes.map(\.name).contains("fork"), "A remote defined by an include target created later is read")
        _ = try await GitService.run(["remote", "remove", "origin"], at: repository.path)
        print("PASS remote configuration comes from the cached filter guard listing")
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
