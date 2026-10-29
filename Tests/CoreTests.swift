import Foundation

@main struct CoreTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw WorkspaceError(message: "FAIL: " + message) }
    }

    static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("agentui-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let importRoot = root.appendingPathComponent("Projects with spaces")
        for name in ["API", "Frontend", ".hidden", "Example.app"] {
            try fm.createDirectory(at: importRoot.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("text".utf8).write(to: importRoot.appendingPathComponent("notes.txt"))
        let children = try WorkspaceDisk.childDirectories(of: importRoot)
        try require(children.map(\.lastPathComponent) == ["API", "Frontend"], "Import only immediate visible directories, excluding app packages and files")
        print("PASS folder import")

        let folder = ProjectFolder(name: "Équipe mobile")
        let project = Project(url: children[0], folderID: folder.id)
        let selection = project.worktrees[0].terminals[0].id
        let state = Workspace(folders: [folder], projects: [project], selection: selection, collapsed: [project.id])
        let stateFile = root.appendingPathComponent("state/workspace.json")
        try WorkspaceDisk.save(state, to: stateFile)
        let loaded = try WorkspaceDisk.load(from: stateFile)
        try require(loaded == state, "Round-trip IDs, grouping, expansion and terminal selection")
        try Data("broken".utf8).write(to: stateFile)
        do { _ = try WorkspaceDisk.load(from: stateFile); throw WorkspaceError(message: "FAIL: corrupt state accepted") }
        catch is DecodingError {}
        let preserved = try Data(contentsOf: stateFile)
        try require(preserved == Data("broken".utf8), "Corrupt data preserved")
        print("PASS persistence and corrupt file protection")

        let projectID = UUID(), worktreeID = UUID()
        let env = ["AGENTUI_PROJECT_ID": projectID.uuidString, "AGENTUI_WORKTREE_ID": worktreeID.uuidString]
        let prompt = "Don't interpolate $(touch /tmp/agentui-unsafe); `echo secret`"
        let request = try AgentCLI.parse(["terminal", "create", "--name", "Review", "--", "claude", prompt], environment: env)
        try require(request.projectID == projectID && request.worktreeID == worktreeID, "Inherited agent context")
        try require(request.command == ["claude", prompt], "Exact command arguments")
        let explicitID = UUID()
        let target = try AgentCLI.parse(["terminal", "create", "--worktree", explicitID.uuidString, "--project", projectID.uuidString], environment: env)
        try require(target.worktreeID == explicitID, "Flag order independence")
        let other = try AgentCLI.parse(["terminal", "create", "--project", projectID.uuidString], environment: env)
        try require(other.worktreeID == nil, "Explicit project doesn't inherit unrelated worktree")
        do { _ = try AgentCLI.parse(["terminal", "create", "--project", "bad"], environment: env); throw WorkspaceError(message: "FAIL: invalid UUID accepted") }
        catch let error as WorkspaceError { try require(error.message.contains("invalide"), "Reject bad IDs") }
        let deletion = try AgentCLI.parse(["worktree", "delete", "--force", "--worktree", explicitID.uuidString], environment: env)
        try require(deletion.action == "worktree.delete" && deletion.worktreeID == explicitID && deletion.force == true, "Parse worktree deletion")
        do { _ = try AgentCLI.parse(["worktree", "delete"], environment: env); throw WorkspaceError(message: "FAIL: implicit deletion accepted") }
        catch let error as WorkspaceError { try require(error.message.contains("--worktree UUID"), "Deletion never targets the current worktree implicitly") }
        do { _ = try AgentCLI.parse(["worktree", "delete", "--worktree", worktreeID.uuidString], environment: env); throw WorkspaceError(message: "FAIL: self deletion accepted") }
        catch let error as WorkspaceError { try require(error.message.contains("autre worktree"), "A terminal cannot delete its own worktree") }
        print("PASS CLI context, argument boundaries, validation")

        let mailbox = root.appendingPathComponent("mailbox")
        try fm.createDirectory(at: mailbox, withIntermediateDirectories: true)
        let valid = mailbox.appendingPathComponent("valid.request")
        try JSONEncoder().encode(request).write(to: valid)
        let decoded = try await BridgeMailbox.request(at: valid)
        try require(decoded.id == request.id, "A regular request file is decoded")
        let linked = mailbox.appendingPathComponent("linked.request")
        try fm.createSymbolicLink(at: linked, withDestinationURL: valid)
        let fifo = mailbox.appendingPathComponent("fifo.request")
        try require(mkfifo(fifo.path, 0o600) == 0, "Create FIFO fixture")
        let oversized = mailbox.appendingPathComponent("oversized.request")
        try Data(repeating: 0x20, count: BridgeMailbox.Envelope.request.limit + 1).write(to: oversized)
        for hostile in [linked, fifo, oversized] {
            do { _ = try await BridgeMailbox.request(at: hostile); throw WorkspaceError(message: "FAIL: hostile request \(hostile.lastPathComponent) accepted") }
            catch let error as WorkspaceError where error.message.hasPrefix("FAIL") { throw error }
            catch {}
        }
        print("PASS bridge mailbox rejects symlinks, FIFOs and oversized requests without blocking")

        try await agentProcessTests(root: root)

        let repository = importRoot.appendingPathComponent("API")
        _ = try await GitService.run(["init", "-b", "main"], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "--allow-empty", "-m", "Fixture"], at: repository.path)
        let gitProject = Project(url: repository)
        let worktree = try await GitService.createWorktree(project: gitProject, branch: "feature/agent-tests", root: root)
        let branch = try await GitService.run(["branch", "--show-current"], at: worktree.path)
        try require(branch == "feature/agent-tests", "New worktree has requested branch")
        let original = try await GitService.run(["branch", "--show-current"], at: repository.path)
        try require(original == "main", "Original checkout unchanged")
        let discovered = try await GitService.existingWorktrees(project: gitProject)
        try require(discovered.contains(where: { $0.path == worktree.path && $0.name == branch }), "Discover existing worktrees and preserve branch name")
        do {
            _ = try await GitService.createWorktree(project: gitProject, branch: "feature/agent-tests", root: root)
            throw WorkspaceError(message: "FAIL: branch used by another worktree accepted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("déjà utilisée"), "Branch used by another worktree rejected")
        }
        let finalWorktrees = try await GitService.existingWorktrees(project: gitProject)
        try require(finalWorktrees.count == discovered.count, "Failed operation doesn't create an extra worktree")
        _ = try await GitService.run(["branch", "existing/feature"], at: repository.path)
        let reused = try await GitService.createWorktree(project: gitProject, branch: "existing/feature", root: root)
        let reusedBranch = try await GitService.run(["branch", "--show-current"], at: reused.path)
        try require(reusedBranch == "existing/feature" && reused.name == "existing/feature", "Existing branch is checked out in the new worktree")
        let mainBranch = try await GitService.run(["branch", "--show-current"], at: repository.path)
        try require(mainBranch == "main", "Original checkout unchanged when reusing a branch")
        try Data("draft".utf8).write(to: URL(fileURLWithPath: reused.path).appendingPathComponent("uncommitted.txt"))
        try await GitService.removeWorktree(project: gitProject, path: reused.path)
        try require(!fm.fileExists(atPath: reused.path), "Deleting a worktree removes its folder, even with uncommitted files")
        let keptBranch = try await GitService.run(["branch", "--list", "existing/feature"], at: repository.path)
        try require(!keptBranch.isEmpty, "Deleting a worktree keeps its branch")
        let afterDeletion = try await GitService.existingWorktrees(project: gitProject)
        try require(afterDeletion.count == discovered.count, "Deleted worktree is no longer registered")
        do {
            try await GitService.removeWorktree(project: gitProject, path: repository.path)
            throw WorkspaceError(message: "FAIL: primary checkout deleted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("principal"), "The primary checkout cannot be deleted")
        }
        do {
            _ = try await GitService.createWorktree(project: gitProject, branch: "--force", root: root)
            throw WorkspaceError(message: "FAIL: option injection accepted")
        } catch let error as WorkspaceError {
            try require(!error.message.hasPrefix("FAIL"), "Invalid branch rejected")
        }
        print("PASS Git worktree creation, discovery, isolation and failures")

        try require(GitRepository.containing(repository.path)?.branch.name == "main", "Read main branch")
        try require(GitRepository.containing(worktree.path)?.branch.name == "feature/agent-tests", "Read worktree gitfile and commondir")
        let source = repository.appendingPathComponent("Sources")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try require(GitRepository.containing(source.path)?.branch.name == "main", "Nested cwd inherits repository branch")
        _ = try await GitService.run(["switch", "-c", "feature/live-switch"], at: repository.path)
        try require(GitRepository.containing(repository.path)?.branch.name == "feature/live-switch", "Detect branch change")
        _ = try await GitService.run(["checkout", "--detach"], at: repository.path)
        let detached = GitRepository.containing(repository.path)?.branch
        try require(detached?.isDetached == true && detached?.name.count == 7, "Detached HEAD is identified honestly")
        _ = try await GitService.run(["switch", "main"], at: repository.path)
        let unborn = importRoot.appendingPathComponent("Frontend")
        _ = try await GitService.run(["init", "-b", "develop"], at: unborn.path)
        try require(GitRepository.containing(unborn.path)?.branch.name == "develop", "Unborn branch before first commit")
        try require(GitRepository.containing(importRoot.path) == nil, "No badge outside a repository")
        print("PASS branch metadata, nested cwd, live switch, detached and unborn HEAD")

        let nested = importRoot.appendingPathComponent("Clients/Mobile")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-b", "main"], at: nested.path)
        let invalid = importRoot.appendingPathComponent("Not a repo/.git")
        try fm.createDirectory(at: invalid, withIntermediateDirectories: true)
        let vendored = repository.appendingPathComponent("Vendor/Embedded")
        try fm.createDirectory(at: vendored, withIntermediateDirectories: true)
        _ = try await GitService.run(["init"], at: vendored.path)
        let alias = importRoot.appendingPathComponent("API alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: repository)
        try fm.createSymbolicLink(at: importRoot.appendingPathComponent("loop"), withDestinationURL: importRoot)
        let repositories = try await RepositoryDiscovery.repositories(in: importRoot)
        try require(Set(repositories.map(\.path)) == Set([repository, unborn, nested].map(WorkspaceDisk.canonicalPath)),
                    "Discover exactly repository roots, deduplicate symlinks, skip loops and repo contents")
        let relative = importRoot.appendingPathComponent("Relative gitfile")
        try fm.createDirectory(at: relative, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-b", "relative", "--separate-git-dir", importRoot.appendingPathComponent(".relative-metadata").path], at: relative.path)
        try "gitdir: ../.relative-metadata\n".write(to: relative.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try require(GitRepository.containing(relative.path)?.branch.name == "relative", "Relative gitfile")
        let containerAlias = root.appendingPathComponent("Studio alias")
        try fm.createSymbolicLink(at: containerAlias, withDestinationURL: importRoot)
        let fromAlias = try await RepositoryDiscovery.repositories(in: containerAlias)
        let fromOriginal = try await RepositoryDiscovery.repositories(in: importRoot)
        try require(fromAlias.map(\.path) == fromOriginal.map(\.path), "A selected symlink to a container imports its repositories")
        if geteuid() != 0 {
            let unreadable = importRoot.appendingPathComponent("Private folder")
            try fm.createDirectory(at: unreadable, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path) }
            let partial = try await RepositoryDiscovery.scan(in: importRoot)
            try require(partial.repositories.map(\.path) == fromOriginal.map(\.path), "Unreadable sibling must not discard accessible repositories")
            try require(partial.skippedDirectories.contains(WorkspaceDisk.canonicalPath(unreadable)), "Report skipped directories")
            do {
                _ = try await RepositoryDiscovery.scan(in: unreadable)
                throw WorkspaceError(message: "FAIL: unreadable root should throw")
            } catch is CocoaError {}
        }
        let oldFolder = try JSONDecoder().decode(ProjectFolder.self, from: Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Existing\"}".utf8))
        try require(oldFolder.sourcePath == nil && oldFolder.parentID == nil && oldFolder.appearance == SidebarAppearance(kind: .folder), "Old virtual folders decode without sourcePath, parent or appearance")
        try require(TerminalProcessDirectory.read(pid: getpid()) != nil, "Read native process cwd")
        print("PASS recursive repository import, gitfiles, symlink deduplication and backward compatibility")
        try await InspectorTests.run(root: root, repository: repository, unborn: unborn)
        try await RegressionTests.run(root: root)
        try await RefreshTests.run(root: root)
        try await UsageTests.run()
        try SettingsTests.run()
        print("All core tests passed.")
    }

    static func agentProcessTests(root: URL) async throws {
        let rolloutID = "01a17eea-ca62-7da2-ab9b-4fe86e40d6a3"
        try require(AgentProcess.codexSessionID(inRolloutPath: "/h/sessions/2026/10/27/rollout-2026-10-27T20-51-18-\(rolloutID).jsonl") == rolloutID
                    && AgentProcess.codexSessionID(inRolloutPath: "/h/sessions/notes.jsonl") == nil, "Read Codex session IDs from rollout paths")
        try require(AgentProcess.copilotSessionID(inPath: "/Users/me/.copilot/session-state/abc/events.jsonl") == "abc", "Read Copilot session IDs")
        try require(AgentProcess.agent(named: ["2.1.312", "claude", "--resume"]) == .claude && AgentProcess.agent(named: ["zsh", "-l"]) == nil,
                    "Recognise agents by process or argument name")

        let start = Date()
        let exact = AgentProcess(agent: .claude, startedAt: start.addingTimeInterval(-600), directory: "/repo", sessionID: "old")
        let recent = AgentProcess(agent: .codex, startedAt: start, directory: "/repo", sessionID: nil)
        let empty = AgentProcess(agent: .codex, startedAt: start.addingTimeInterval(60), directory: "/repo", sessionID: nil)
        let conversations = ["/repo": [
            AgentConversation(agent: .claude, sessionID: "new", title: "Autre conversation", updatedAt: start.addingTimeInterval(30)),
            AgentConversation(agent: .claude, sessionID: "old", title: "Corriger la connexion", updatedAt: start.addingTimeInterval(-300)),
            AgentConversation(agent: .codex, sessionID: "c1", title: String(repeating: "Long titre ", count: 8), updatedAt: start.addingTimeInterval(10)),
            AgentConversation(agent: .codex, sessionID: "c0", title: "Avant le lancement", updatedAt: start.addingTimeInterval(-60)),
        ]]
        let first = UUID(), second = UUID(), third = UUID()
        let titles = AgentProcess.titles(for: [first: exact, second: recent, third: empty], conversations: conversations)
        try require(titles[first] == "Corriger la connexion", "A known session ID picks its own conversation even when another is newer")
        try require(titles[second]?.count == 40 && titles[second]?.hasSuffix("…") == true, "Without a session ID, the conversation updated since launch is used and shortened")
        try require(titles[third] == nil, "Conversations older than the process or already claimed are never used")

        let fakeHome = root.appendingPathComponent("agent-home")
        let bin = root.appendingPathComponent("agent-bin")
        try FileManager.default.createDirectory(at: fakeHome.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fakeClaude = bin.appendingPathComponent("claude")
        try "#!/bin/sh\nsleep 10\n".write(to: fakeClaude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeClaude.path)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "\"$0\"; true", fakeClaude.path]
        shell.currentDirectoryURL = root
        try shell.run()
        defer { shell.terminate() }
        var detected: AgentProcess?
        for _ in 0..<50 {
            detected = AgentProcess.find(under: shell.processIdentifier, fallbackDirectory: "/", home: fakeHome)
            if detected != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let detected else { throw WorkspaceError(message: "FAIL: agent child process not found") }
        try require(detected.agent == .claude && detected.directory == WorkspaceDisk.canonicalPath(root) && detected.sessionID == nil, "Find an agent child process and its directory")
        let childPID = agentChild(of: shell.processIdentifier)
        try #"{"pid":\#(childPID),"sessionId":"session-42"}"#.write(to: fakeHome.appendingPathComponent(".claude/sessions/\(childPID).json"), atomically: true, encoding: .utf8)
        let withSession = AgentProcess.find(under: shell.processIdentifier, fallbackDirectory: "/", home: fakeHome)
        try require(withSession?.sessionID == "session-42", "Read the Claude session of the agent process")
        print("PASS agent process detection and conversation titles")
    }

    static func agentChild(of pid: Int32) -> Int32 {
        var buffer = [Int32](repeating: 0, count: 16)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(buffer.count * 4))
        return bytes > 0 ? buffer[0] : 0
    }
}
