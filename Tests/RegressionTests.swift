import Foundation

@MainActor enum RegressionTests {
    static func run(root: URL) async throws {
        let fm = FileManager.default
        let repo = root.appendingPathComponent("review-regressions")
        try fm.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-b", "main"], at: repo.path)
        for name in ["a[1].txt", "a1.txt"] { try "before\n".write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        _ = try await GitService.run(["add", "."], at: repo.path)
        _ = try await GitService.run(["-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "fixture"], at: repo.path)
        for name in ["a[1].txt", "a1.txt"] { try "after\n".write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        let snapshot = try await InspectorService.localGit(at: repo.path)
        let change = snapshot.changes.first { $0.path == "a[1].txt" }!
        let diff = try await InspectorService.diff(change, at: repo.path)
        try CoreTests.require(diff.sections.contains { $0.patch.contains("diff --git a/a[1].txt") } && !diff.sections.contains { $0.patch.contains("diff --git a/a1.txt") }, "Literal diff path cannot match a second file")
        let text = root.appendingPathComponent("utf8-boundary.txt")
        for character in ["é", "€", "🙂"] {
            for offset in 1..<character.utf8.count {
                try (String(repeating: "a", count: 131_072 - offset) + character + "tail").write(to: text, atomically: true, encoding: .utf8)
                let preview = try await InspectorService.textFile(text)
                try CoreTests.require(preview.contains("128 Ko") && !preview.contains("�"), "Truncate UTF-8 at a scalar boundary")
            }
        }
        try Data([0xFF, 0x61]).write(to: text)
        do { _ = try await InspectorService.textFile(text); throw WorkspaceError(message: "FAIL: invalid UTF-8 accepted") }
        catch is ReadCommandError {}
        print("PASS literal Git paths and UTF-8 truncation across 2/3/4-byte scalars")

        let previewFile = root.appendingPathComponent("preview.txt")
        try "hello\n".write(to: previewFile, atomically: true, encoding: .utf8)
        let previews = InspectorPreviews()
        previews.open(previewFile)
        previews.diff(change, at: repo.path)
        try CoreTests.require(previews.isLoading && previews.request == .file(previewFile), "A second preview request is ignored while one is loading")
        await previews.load()
        guard case .file(let loadedFile)? = previews.current else { throw WorkspaceError(message: "FAIL: file preview not loaded") }
        try CoreTests.require(loadedFile.text == "hello\n" && !previews.isLoading && previews.error == nil, "A loaded preview is presented and clears the request")
        previews.open(root.appendingPathComponent("missing.txt"))
        await previews.load()
        try CoreTests.require(previews.error != nil && !previews.isLoading, "A failed preview reports its error and clears the request")
        previews.error = nil
        previews.diff(change, at: repo.path)
        let cancelled = Task { await previews.load() }
        cancelled.cancel()
        await cancelled.value
        try CoreTests.require(previews.error == nil && previews.request == .diff(change, root: repo.path), "A cancelled preview is neither reported as an error nor forgotten")
        print("PASS preview loading, deduplication, failure and cancellation")

        let untrusted = root.appendingPathComponent("untrusted-repo")
        let markers = root.appendingPathComponent("untrusted-markers")
        try fm.createDirectory(at: markers, withIntermediateDirectories: true)
        let payload = root.appendingPathComponent("payload.sh")
        try "#!/bin/sh\ntouch '\(markers.path)'/\"$1\"\ncase \"$1\" in *-process) exit 1 ;; esac\ncat\n".write(to: payload, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: payload.path)
        let submodule = root.appendingPathComponent("untrusted-submodule")
        for (repository, driver) in [(untrusted, "payload"), (submodule, "nestedpayload")] {
            try fm.createDirectory(at: repository, withIntermediateDirectories: true)
            _ = try await GitService.run(["init", "-b", "main"], at: repository.path)
            try "* filter=\(driver)\n".write(to: repository.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
            try "before\n".write(to: repository.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            _ = try await GitService.run(["add", "."], at: repository.path)
            _ = try await GitService.run(["-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "fixture"], at: repository.path)
        }
        _ = try await GitService.run(["-c", "protocol.file.allow=always", "submodule", "add", submodule.path, "nested"], at: untrusted.path)
        _ = try await GitService.run(["-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "submodule"], at: untrusted.path)
        let nested = untrusted.appendingPathComponent("nested")
        for (repository, name, driver) in [(untrusted, "parent", "payload"), (nested, "submodule", "nestedpayload")] {
            _ = try await GitService.run(["config", "core.fsmonitor", "\(payload.path) \(name)-fsmonitor"], at: repository.path)
            _ = try await GitService.run(["config", "filter.\(driver).clean", "\(payload.path) \(name)-clean"], at: repository.path)
            _ = try await GitService.run(["config", "filter.\(driver).process", "\(payload.path) \(name)-process"], at: repository.path)
            try "after!\n".write(to: repository.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        }
        let untrustedSnapshot = try await InspectorService.localGit(at: untrusted.path)
        let modified = GitChange(path: "file.txt", originalPath: nil, indexStatus: " ", worktreeStatus: "M")
        _ = try await InspectorService.diff(modified, at: untrusted.path)
        _ = try await InspectorService.diff(GitChange(path: "nested", originalPath: nil, indexStatus: " ", worktreeStatus: "M"), at: untrusted.path)
        _ = try await GitService.existingWorktrees(project: Project(url: untrusted))
        let triggered = try fm.contentsOfDirectory(atPath: markers.path).sorted()
        try CoreTests.require(triggered.isEmpty, "Repository and submodule commands never run during automatic Git reads, got \(triggered)")
        try CoreTests.require(untrustedSnapshot.changes == [modified], "Status still reports real changes with filters disabled, got \(untrustedSnapshot.changes.map(\.path))")

        let listing = Data("global\0filter.lfs.process\0system\0filter.media.clean\0local\0filter.payload.clean\0worktree\0filter.Tree.v2.smudge\0unknown\0filter.other.process\0local\0filter.clean\0command\0filter.cli.clean\0local\0core.bare\0".utf8)
        let drivers = GitConfiguration.untrustedFilterDrivers(in: listing)
        try CoreTests.require(drivers == ["payload", "Tree.v2", "other"], "Only repository-scoped filter drivers are disabled, got \(drivers)")
        let disabled = GitConfiguration.disabling(filterDrivers: ["payload"])
        try CoreTests.require(disabled == ["filter.payload.clean": "", "filter.payload.smudge": "", "filter.payload.process": "", "filter.payload.required": "false"],
                              "A disabled driver has no command and is not required")
        let inherited = CommandRunner.environment(readOnly: true, base: ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "Tests"])
        try CoreTests.require(inherited["GIT_CONFIG_COUNT"] == "2" && inherited["GIT_CONFIG_KEY_0"] == "user.name"
                              && inherited["GIT_CONFIG_KEY_1"] == "core.fsmonitor" && inherited["GIT_CONFIG_VALUE_1"] == "false",
                              "Hardened Git configuration is appended to inherited command-line configuration")
        for bogus in ["-1", "many"] {
            let environment = CommandRunner.environment(readOnly: true, base: ["GIT_CONFIG_COUNT": bogus])
            try CoreTests.require(environment["GIT_CONFIG_COUNT"] == "1" && environment["GIT_CONFIG_KEY_0"] == "core.fsmonitor",
                                  "An invalid inherited GIT_CONFIG_COUNT (\(bogus)) cannot cancel the hardening")
        }
        print("PASS repository-controlled fsmonitor, filter and submodule commands are disabled")

        let hook = repo.appendingPathComponent(".git/hooks/post-checkout")
        let marker = root.appendingPathComponent("hook-pid")
        try "#!/bin/sh\necho $$ > '\(marker.path)'\nexec /bin/sleep 30\n".write(to: hook, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        let project = Project(url: repo)
        let task = Task { try await GitService.createWorktree(project: project, branch: "cancelled", root: root) }
        for _ in 0..<200 {
            if fm.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let hookPID = Int32(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        let cancellationStart = Date()
        task.cancel()
        var partialPath: String?
        do { _ = try await task.value; throw WorkspaceError(message: "FAIL: cancelled mutation reported success") }
        catch let error as WorktreeCreationError {
            try CoreTests.require(error.reason.contains("annulée"), "Cancellation is reported honestly")
            partialPath = error.path
        }
        try CoreTests.require(Date().timeIntervalSince(cancellationStart) < 3, "Cancellation releases blocked Git promptly")
        for _ in 0..<100 {
            if TerminalProcessDirectory.read(pid: hookPID) == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try CoreTests.require(TerminalProcessDirectory.read(pid: hookPID) == nil, "Cancellation also stops the hook process")
        let trees = try await GitService.existingWorktrees(project: project)
        try CoreTests.require(trees.contains { $0.path == partialPath }, "Partial worktree is preserved and discoverable")
        do {
            _ = try await GitService.createWorktree(project: project, branch: "timed-out", root: root, timeout: 0.2)
            throw WorkspaceError(message: "FAIL: stalled worktree did not time out")
        } catch let error as WorktreeCreationError { try CoreTests.require(error.reason.contains("temps"), "Timeout explains partial creation") }
        try fm.removeItem(at: hook)
        print("PASS worktree cancellation, hook termination, deadline and partial creation recovery")

        let file = root.appendingPathComponent("ordered-workspace.json")
        let writer = WorkspaceWriter(fileURL: file)
        let older = Workspace(folders: [ProjectFolder(name: "old")])
        let newer = Workspace(folders: [ProjectFolder(name: "new")])
        try await writer.write(newer, revision: 2)
        try await writer.write(older, revision: 1)
        let stored = try WorkspaceDisk.load(from: file)
        try CoreTests.require(stored == newer, "Late old snapshot cannot overwrite newer disk state")
        print("PASS ordered persistence")

        let fixture = InspectorFixture()
        let model = InspectorStore(readLocal: { _ in await fixture.local() }, readRemote: { try await fixture.remote($0) })
        let monitoring = Task { await model.monitor(path: repo.path, localInterval: .milliseconds(10), remoteInterval: .milliseconds(10)) }
        for _ in 0..<200 {
            if await fixture.remoteStarted { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await fixture.changeHead()
        for _ in 0..<200 {
            if model.local?.headSHA == "new" { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try CoreTests.require(model.local?.headSHA == "new" && model.github == nil, "Local polling advances while first GitHub request is pending")
        for _ in 0..<200 {
            if model.github?.repository.nameWithOwner == "new" { break }
            try CoreTests.require(model.github?.repository.nameWithOwner != "old", "Reject late GitHub response for previous HEAD")
            try await Task.sleep(for: .milliseconds(5))
        }
        try CoreTests.require(model.github?.repository.nameWithOwner == "new", "Fetch remote state for new HEAD")
        monitoring.cancel()
        await monitoring.value
        try CoreTests.require(!model.loading, "Inspector cancellation resets loading state")
        let count = await fixture.localCount
        try await Task.sleep(for: .milliseconds(50))
        let stoppedCount = await fixture.localCount
        try CoreTests.require(count == stoppedCount, "Hiding inspector stops both loops")
        print("PASS independent Git/GitHub polling, stale response rejection and lifecycle cancellation")
    }
}

private actor InspectorFixture {
    var localCount = 0
    var remoteStarted = false
    private var head = "old"
    func changeHead() { head = "new" }
    func local() -> LocalGitSnapshot {
        localCount += 1
        return LocalGitSnapshot(root: "/fixture", branch: GitBranch(name: "main"), headSHA: head, changes: [])
    }
    func remote(_ local: LocalGitSnapshot) async throws -> GitHubSnapshot {
        remoteStarted = true
        try await Task.sleep(for: .milliseconds(local.headSHA == "old" ? 250 : 10))
        return GitHubSnapshot(repository: GitHubRepository(nameWithOwner: local.headSHA!, url: "https://github.com/fixture/app", description: nil), pullRequest: nil, runs: [], pullRequestError: nil, checksError: nil)
    }
}
