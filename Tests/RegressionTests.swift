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

        let monitorMarker = root.appendingPathComponent("fsmonitor-ran")
        let monitor = root.appendingPathComponent("fsmonitor.sh")
        try "#!/bin/sh\ntouch '\(monitorMarker.path)'\n".write(to: monitor, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: monitor.path)
        _ = try await GitService.run(["config", "core.fsmonitor", monitor.path], at: repo.path)
        _ = try await InspectorService.localGit(at: repo.path)
        _ = try await InspectorService.diff(change, at: repo.path)
        _ = try await GitService.existingWorktrees(project: Project(url: repo))
        try CoreTests.require(!fm.fileExists(atPath: monitorMarker.path), "Repository fsmonitor commands never run during automatic Git reads")
        _ = try await GitService.run(["config", "--unset", "core.fsmonitor"], at: repo.path)
        let inherited = CommandRunner.environment(readOnly: true, base: ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "Tests"])
        try CoreTests.require(inherited["GIT_CONFIG_COUNT"] == "2" && inherited["GIT_CONFIG_KEY_0"] == "user.name"
                              && inherited["GIT_CONFIG_KEY_1"] == "core.fsmonitor" && inherited["GIT_CONFIG_VALUE_1"] == "false",
                              "Hardened Git configuration is appended to inherited command-line configuration")
        print("PASS repository-controlled fsmonitor commands are disabled")

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
