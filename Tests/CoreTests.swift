import CoreGraphics
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

        var floating = FloatingTerminal()
        let first = floating.addTab(path: "/one")
        let second = floating.addTab(path: "/two")
        try require(floating.tabs.count == 2 && floating.focusedID == second.id, "A new floating tab gets the focus")
        let right = try floating.split(second.id, axis: .horizontal, path: "/two").unwrapped()
        try require(floating.selectedTab?.terminalIDs == [second.id, right.id] && floating.focusedID == right.id, "Splitting focuses the new pane in the same tab")
        floating.selectTab(offset: 1)
        try require(floating.focusedID == first.id, "Next tab wraps around")
        floating.selectTab(offset: -1)
        try require(floating.focusedID == right.id, "Selecting a tab restores its last focused pane")
        let beforeFocusChange = floating
        floating.focus(second.id)
        floating.select(.terminal(first.id))
        try require(floating.hasSameLayout(as: beforeFocusChange) && floating != beforeFocusChange, "Focus and tab changes keep the persisted layout")
        var restructured = floating
        restructured.addTab(path: "/three")
        try require(!restructured.hasSameLayout(as: floating), "A new tab changes the persisted layout")
        restructured = floating
        restructured.split(first.id, axis: .vertical, path: "/one")
        try require(!restructured.hasSameLayout(as: floating), "A split changes the persisted layout")
        restructured = floating
        restructured.close(second.id)
        try require(!restructured.hasSameLayout(as: floating), "Closing a pane changes the persisted layout")
        floating.select(floating.tabs[1])
        let encodedFloating = try JSONEncoder().encode(floating)
        let persistedKeys = try (JSONSerialization.jsonObject(with: encodedFloating) as? [String: Any]).unwrapped().keys
        try require(Set(persistedKeys) == ["panes", "tabs", "focusHistory"], "The floating terminal persists its panes, tabs and focus order")
        let decodedFloating = try JSONDecoder().decode(FloatingTerminal.self, from: encodedFloating)
        try require(decodedFloating == floating && decodedFloating.focusedID == second.id && decodedFloating.selectedTab == floating.selectedTab, "Floating tabs, splits and focus round-trip")
        let floatingContext = TerminalContext(floating: FloatingTerminal.Pane(path: "/one"))
        try require(floatingContext.isFloating && floatingContext.worktree.path == "/one", "Floating terminals are told apart from workspace terminals")
        let floatingRequest = try AgentCLI.parse(["terminal", "create"], environment: [:], currentDirectory: "/one")
        try require(floatingRequest.projectID == nil && floatingRequest.worktreeID == nil && floatingRequest.directory == "/one", "Without exported IDs the CLI infers the project from the current folder")
        floating.close(right.id)
        try require(floating.selectedTab == .terminal(second.id) && floating.focusedID == second.id, "Closing a pane focuses its neighbour")
        floating.close(second.id)
        try require(floating.tabs == [.terminal(first.id)] && floating.focusedID == first.id, "Closing a tab falls back to the last used one")
        floating.close(first.id)
        try require(floating.isEmpty && floating.focusedID == nil && floating.panes.isEmpty, "Closing the last pane empties the floating terminal")
        print("PASS floating terminal tabs, splits and focus")

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
        catch let error as WorkspaceError { try require(error.message.contains("Invalid"), "Reject bad IDs") }
        let deletion = try AgentCLI.parse(["worktree", "delete", "--force", "--worktree", explicitID.uuidString], environment: env)
        try require(deletion.action == "worktree.delete" && deletion.worktreeID == explicitID && deletion.force == true && deletion.deleteBranch == nil, "Parse worktree deletion")
        let branchDeletion = try AgentCLI.parse(["worktree", "delete", "--worktree", explicitID.uuidString, "--delete-branch"], environment: env)
        try require(branchDeletion.deleteBranch == true && branchDeletion.force == nil && branchDeletion.forceBranch == nil, "Parse worktree deletion with its branch")
        let forcedFiles = try AgentCLI.parse(["worktree", "delete", "--worktree", explicitID.uuidString, "--delete-branch", "--force"], environment: env)
        try require(forcedFiles.force == true && forcedFiles.forceBranch == nil, "--force discards working files but doesn't force the branch deletion")
        let forcedBranch = try AgentCLI.parse(["worktree", "delete", "--worktree", explicitID.uuidString, "--delete-branch", "--force-branch"], environment: env)
        try require(forcedBranch.forceBranch == true && forcedBranch.force == nil, "--force-branch alone forces the branch deletion")
        let removals = try [forcedBranch.branchRemoval, branchDeletion.branchRemoval, deletion.branchRemoval]
        try require(removals == [.force, .merged, .keep],
                    "--delete-branch deletes a merged branch, --force-branch any branch")
        do {
            _ = try AgentCLI.parse(["worktree", "delete", "--worktree", explicitID.uuidString, "--force-branch"], environment: env)
            throw WorkspaceError(message: "FAIL: --force-branch accepted without --delete-branch")
        } catch let error as WorkspaceError {
            try require(error.message.contains("--delete-branch") && !error.message.hasPrefix("FAIL"), "--force-branch requires --delete-branch")
        }
        var forcedOnly = deletion
        forcedOnly.forceBranch = true
        do {
            _ = try forcedOnly.branchRemoval
            throw WorkspaceError(message: "FAIL: a request forcing the branch without deleting it accepted")
        } catch let error as WorkspaceError {
            try require(!error.message.hasPrefix("FAIL"), "The bridge refuses to force a branch deletion that wasn't asked for")
        }
        do { _ = try AgentCLI.parse(["worktree", "create", "--branch", "x", "--force-branch"], environment: env); throw WorkspaceError(message: "FAIL: --force-branch accepted on creation") }
        catch let error as WorkspaceError { try require(!error.message.hasPrefix("FAIL"), "--force-branch only applies to deletion") }
        do { _ = try AgentCLI.parse(["worktree", "create", "--branch", "x", "--delete-branch"], environment: env); throw WorkspaceError(message: "FAIL: --delete-branch accepted on creation") }
        catch let error as WorkspaceError { try require(!error.message.hasPrefix("FAIL"), "--delete-branch only applies to deletion") }
        do { _ = try AgentCLI.parse(["worktree", "delete"], environment: env); throw WorkspaceError(message: "FAIL: implicit deletion accepted") }
        catch let error as WorkspaceError { try require(error.message.contains("--worktree UUID"), "Deletion never targets the current worktree implicitly") }
        do { _ = try AgentCLI.parse(["worktree", "delete", "--worktree", worktreeID.uuidString], environment: env); throw WorkspaceError(message: "FAIL: self deletion accepted") }
        catch let error as WorkspaceError { try require(error.message.contains("another worktree"), "A terminal cannot delete its own worktree") }
        let inherited = try AgentCLI.parse(["terminal", "create"], environment: env, currentDirectory: "/tmp")
        try require(inherited.projectID == projectID && inherited.directory == "/tmp", "An AgentUI terminal keeps its context and sends its directory")
        let worktreeOnly = try AgentCLI.parse(["terminal", "create", "--worktree", explicitID.uuidString], environment: env)
        try require(worktreeOnly.projectID == nil && worktreeOnly.worktreeID == explicitID, "--worktree alone lets the app find its project")
        let foreignDeletion = try AgentCLI.parse(["worktree", "delete", "--worktree", explicitID.uuidString], environment: env)
        try require(foreignDeletion.projectID == nil, "Deleting another project's worktree ignores the terminal's project")
        let outside = try AgentCLI.parse(["terminal", "create"], environment: [:], currentDirectory: "/work/app/Sources")
        try require(outside.projectID == nil && outside.directory == "/work/app/Sources", "Outside AgentUI, the current directory is sent")
        let mainID = UUID(), featureID = UUID()
        var locatedProject = Project(url: URL(fileURLWithPath: "/work/app"))
        locatedProject.worktrees = [
            Worktree(id: mainID, name: "main", path: "/work/app", isPrimary: true),
            Worktree(id: featureID, name: "feature", path: "/work/app/.worktrees/feature")
        ]
        let located = Workspace(projects: [locatedProject])
        try require(located.location(containing: "/work/app/Sources")?.worktreeID == mainID, "A subfolder belongs to its worktree")
        try require(located.location(containing: "/work/app/.worktrees/feature/src")?.worktreeID == featureID, "The deepest worktree wins")
        try require(located.location(containing: "/work/application") == nil, "Sibling folders with a common prefix are not matched")
        let registry = root.appendingPathComponent("Instances")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        let liveInstance = root.appendingPathComponent("live-instance"), deadInstance = root.appendingPathComponent("dead-instance")
        try FileManager.default.createDirectory(at: liveInstance, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deadInstance, withIntermediateDirectories: true)
        try require(AgentCLI.runningInstance(in: registry) == nil, "No registered instance means AgentUI is closed")
        try Data().write(to: registry.appendingPathComponent("1.sb-pending"))
        try require(AgentCLI.runningInstance(in: registry) == nil, "An atomic write in progress is not an instance")
        try require(FileManager.default.fileExists(atPath: registry.appendingPathComponent("1.sb-pending").path), "An atomic write in progress is left alone")
        try deadInstance.path.write(to: registry.appendingPathComponent("999999"), atomically: true, encoding: .utf8)
        try require(AgentCLI.runningInstance(in: registry) == nil, "A crashed instance is ignored")
        try require(!FileManager.default.fileExists(atPath: registry.appendingPathComponent("999999").path), "A crashed instance is unregistered")
        try liveInstance.path.write(to: registry.appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier)), atomically: true, encoding: .utf8)
        try require(AgentCLI.runningInstance(in: registry)?.path == liveInstance.path, "A running instance is found")
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
        try terminalLayoutTests()
        try homeAbbreviationTests()

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
            try require(error.message.contains("already used"), "Branch used by another worktree rejected")
        }
        let finalWorktrees = try await GitService.existingWorktrees(project: gitProject)
        try require(finalWorktrees.count == discovered.count, "Failed operation doesn't create an extra worktree")
        _ = try await GitService.run(["branch", "existing/feature"], at: repository.path)
        let available = try await GitService.availableBranches(project: gitProject)
        try require(available == [BranchSuggestion(name: "existing/feature", origin: .local)], "Suggest free local branches, not checked-out ones")
        let parsed = GitService.branchSuggestions(from: """
        refs/heads/main\t/projects/API
        refs/heads/fix/login\t
        refs/remotes/origin/HEAD\t
        refs/remotes/origin/main\t
        refs/remotes/origin/fix/login\t
        refs/remotes/upstream/feature/review\t
        refs/remotes/origin/feature/review\t
        refs/remotes/gh/team/release\t
        """, remotes: ["origin", "gh", "gh/team", "upstream"])
        try require(parsed == [BranchSuggestion(name: "fix/login", origin: .local),
                               BranchSuggestion(name: "feature/review", origin: .remote("upstream")),
                               BranchSuggestion(name: "release", origin: .remote("gh/team"))],
                    "Remote branches are suggested once, without their remote prefix, even when the remote name has a slash")
        try require(BranchSuggestion(name: "feature/review", origin: .local).matches("REVIEW")
                    && !BranchSuggestion(name: "feature/review", origin: .local).matches("feature/review"),
                    "Suggestions match case-insensitively and hide once typed in full")
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
        try await branchDeletionTests(project: gitProject, root: root)
        let afterDeletion = try await GitService.existingWorktrees(project: gitProject)
        try require(afterDeletion.count == discovered.count, "Deleted worktree is no longer registered")
        do {
            try await GitService.removeWorktree(project: gitProject, path: repository.path)
            throw WorkspaceError(message: "FAIL: primary checkout deleted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("main folder"), "The primary checkout cannot be deleted")
        }
        do {
            _ = try await GitService.createWorktree(project: gitProject, branch: "--force", root: root)
            throw WorkspaceError(message: "FAIL: option injection accepted")
        } catch let error as WorkspaceError {
            try require(!error.message.hasPrefix("FAIL"), "Invalid branch rejected")
        }
        let upstream = root.appendingPathComponent("Upstream")
        try fm.createDirectory(at: upstream, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-b", "main"], at: upstream.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "--allow-empty", "-m", "Upstream"], at: upstream.path)
        _ = try await GitService.run(["branch", "shared/topic"], at: upstream.path)
        for remote in ["mirror", "gh/team"] {
            _ = try await GitService.run(["remote", "add", remote, upstream.path], at: repository.path)
        }
        try await GitService.fetchRemotes(project: gitProject)
        let remoteBranches = try await GitService.availableBranches(project: gitProject)
        try require(remoteBranches.filter { $0.name == "shared/topic" }.count == 1, "A branch present on two remotes is suggested once")
        let tracked = try await GitService.createWorktree(project: gitProject, branch: "shared/topic", remote: "gh/team", root: root)
        let upstreamBranch = try await GitService.run(["rev-parse", "--abbrev-ref", "@{upstream}"], at: tracked.path)
        try require(upstreamBranch == "gh/team/shared/topic", "A remote branch shared by several remotes tracks the chosen remote")
        try await GitService.removeWorktree(project: gitProject, path: tracked.path)
        for remote in ["mirror", "gh/team"] {
            _ = try await GitService.run(["remote", "remove", remote], at: repository.path)
        }
        _ = try await GitService.run(["branch", "-D", "shared/topic"], at: repository.path)
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
        let main = GitRepository.containing(repository.path)
        try require(GitRepository.containing(worktree.path)?.divergentBranch(from: main) == GitBranch(name: "feature/agent-tests")
                        && GitRepository.containing(source.path)?.divergentBranch(from: main) == nil
                        && GitRepository.containing(unborn.path)?.divergentBranch(from: main) == nil,
                    "Only another worktree of the same repository diverges from a worktree's branch")
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
        let submodule = repository.appendingPathComponent("Modules/Shared")
        try fm.createDirectory(at: submodule.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: repository.appendingPathComponent(".git/modules"), withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "--separate-git-dir", repository.appendingPathComponent(".git/modules/Shared").path, submodule.path], at: repository.path)
        let buildOutput = repository.appendingPathComponent("target/checkout")
        try fm.createDirectory(at: buildOutput, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q"], at: buildOutput.path)
        let nestedWorktree = repository.appendingPathComponent("Checkouts/review")
        _ = try await GitService.run(["worktree", "add", "-q", "-b", "nested/review", nestedWorktree.path], at: repository.path)
        let repositories = try await RepositoryDiscovery.repositories(in: importRoot)
        _ = try await GitService.run(["worktree", "remove", "--force", nestedWorktree.path], at: repository.path)
        _ = try await GitService.run(["branch", "-D", "nested/review"], at: repository.path)
        try require(Set(repositories.map(\.path)) == Set([repository, unborn, nested, vendored].map(WorkspacePath.canonical)),
                    "Discover nested repositories but skip submodules, nested worktrees and build output, deduplicate symlinks and skip loops")
        let plan = RepositoryImport(source: importRoot, discovery: RepositoryDiscoveryResult(repositories: repositories, skippedDirectories: []), target: nil)
        let rootPath = WorkspacePath.canonical(importRoot)
        let repositoryPath = WorkspacePath.canonical(repository)
        let vendoredPath = WorkspacePath.canonical(vendored)
        let apiNode = plan.tree.children?.first { $0.path == repositoryPath }
        try require(plan.tree.path == rootPath && plan.tree.repositoryPaths.count == 4, "Import tree keeps every repository")
        try require(apiNode?.children?.map(\.id) == ["repository:\(repositoryPath)", "folder:\(repositoryPath)/Vendor"],
                    "A repository containing repositories becomes a folder holding itself and its nested hierarchy")
        try require(apiNode?.children?.last?.children?.map(\.path) == [vendoredPath], "Intermediate directories become folders")
        try require(apiNode?.keeping([repositoryPath]) == .repository(path: repositoryPath, name: repository.lastPathComponent),
                    "A repository folder without selected nested repositories collapses back to the repository")
        try require(plan.tree.keeping([]) == nil && plan.preview(flattened: true).children?.count == 4, "Empty selection imports nothing and flat preview lists every repository")
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
            try require(partial.skippedDirectories.contains(WorkspacePath.canonical(unreadable)), "Report skipped directories")
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

    static func branchDeletionTests(project: Project, root: URL) async throws {
        try require(WorktreeBranch(GitBranch(name: "feature"), defaultBranches: ["main"], checkedOutElsewhere: ["main"]) == .deletable("feature"),
                    "A named branch that is not the main one is deletable")
        try require(WorktreeBranch(GitBranch(name: "main"), defaultBranches: ["main"], checkedOutElsewhere: []) == .protected("main", .defaultBranch),
                    "The default branch is protected")
        try require(WorktreeBranch(GitBranch(name: "shared"), defaultBranches: [], checkedOutElsewhere: ["shared"]) == .protected("shared", .checkedOutElsewhere),
                    "A branch checked out in another worktree is protected")
        try require(WorktreeBranch(GitBranch(name: "abc1234", isDetached: true), defaultBranches: [], checkedOutElsewhere: []) == .none
                        && WorktreeBranch(nil, defaultBranches: [], checkedOutElsewhere: []) == .none, "A detached HEAD has no branch to delete")
        try require(BranchRemoval.keep.arguments(for: "x") == nil && BranchRemoval.merged.arguments(for: "x") == ["branch", "-D", "--", "x"]
                        && BranchRemoval.force.arguments(for: "x") == ["branch", "-D", "--", "x"]
                        && BranchRemoval.merged.requiresMerge && !BranchRemoval.force.requiresMerge, "Branch deletion arguments")
        try require(BranchCleanup.deleted("x").isDeleted && BranchCleanup.kept("x", reason: "r").failure != nil
                        && BranchCleanup.untouched.notice != nil && BranchCleanup.deleted("x").failure == nil, "Branch cleanup reporting")

        let shared = root.appendingPathComponent("cleanup-shared-main")
        _ = try await GitService.run(["worktree", "add", "-q", "-f", shared.path, "main"], at: project.path)
        let sharedBranch = await GitBranchProtection.report(at: shared.path, checkedOutElsewhere: []).branch
        try require(sharedBranch == .protected("main", .defaultBranch),
                    "The branch of the project's main folder is never deletable from another worktree")
        try await GitService.removeWorktree(project: project, path: shared.path)
        let merged = try await GitService.createWorktree(project: project, branch: "cleanup/merged", root: root)
        let mergedBranch = await GitBranchProtection.report(at: merged.path, checkedOutElsewhere: []).branch
        try require(mergedBranch == .deletable("cleanup/merged"), "A merged worktree branch is deletable")
        _ = try await GitService.run(["update-ref", "refs/remotes/origin/cleanup/merged", "HEAD"], at: project.path)
        _ = try await GitService.run(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/cleanup/merged"], at: project.path)
        let remoteDefaultBranch = await GitBranchProtection.report(at: merged.path, checkedOutElsewhere: []).branch
        try require(remoteDefaultBranch == .protected("cleanup/merged", .defaultBranch), "The branch a remote HEAD points to is the default branch")
        _ = try await GitService.run(["symbolic-ref", "--delete", "refs/remotes/origin/HEAD"], at: project.path)
        _ = try await GitService.run(["update-ref", "-d", "refs/remotes/origin/cleanup/merged"], at: project.path)
        try await GitService.removeWorktree(project: project, path: merged.path)
        try await deleteBranch("cleanup/merged", .merged, project: project)
        let mergedLeft = try await GitService.run(["branch", "--list", "cleanup/merged"], at: project.path)
        try require(mergedLeft.isEmpty, "A merged branch is deleted with its worktree")

        let unmerged = try await GitService.createWorktree(project: project, branch: "cleanup/unmerged", root: root)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "--allow-empty", "-m", "Work"], at: unmerged.path)
        try await GitService.removeWorktree(project: project, path: unmerged.path)
        do {
            try await deleteBranch("cleanup/unmerged", .merged, project: project)
            throw WorkspaceError(message: "FAIL: unmerged branch deleted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("isn’t fully merged") && error.message.contains("git branch -D cleanup/unmerged"), "An unmerged branch is refused with a clear message")
        }
        let unmergedLeft = try await GitService.run(["branch", "--list", "cleanup/unmerged"], at: project.path)
        try require(!unmergedLeft.isEmpty, "An unmerged branch is kept")
        try await deleteBranch("cleanup/unmerged", .force, project: project)
        let forcedLeft = try await GitService.run(["branch", "--list", "cleanup/unmerged"], at: project.path)
        try require(forcedLeft.isEmpty, "Forcing deletes an unmerged branch")

        let detached = try await GitService.createWorktree(project: project, branch: "cleanup/detached", root: root)
        _ = try await GitService.run(["checkout", "--detach"], at: detached.path)
        let detachedBranch = await GitBranchProtection.report(at: detached.path, checkedOutElsewhere: []).branch
        try require(detachedBranch == WorktreeBranch.none, "A detached worktree has no branch to delete")
        let missingBranch = await GitBranchProtection.report(at: root.appendingPathComponent("cleanup-missing").path, checkedOutElsewhere: []).branch
        try require(missingBranch == .unreadable && missingBranch.deletableName == nil && missingBranch.refusal != nil,
                    "A branch that can't be checked is never deleted, and the deletion stops before removing anything")
        try await GitService.removeWorktree(project: project, path: detached.path)
        _ = try await GitService.run(["branch", "-D", "cleanup/detached"], at: project.path)

        let local = root.appendingPathComponent("cleanup-local-only")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: local.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Initial"], at: local.path)
        _ = try await GitService.run(["checkout", "-q", "-b", "feature"], at: local.path)
        _ = try await GitService.run(["pack-refs", "--all"], at: local.path)
        let localProject = Project(url: local)
        let linkedMain = root.appendingPathComponent("cleanup-local-main")
        _ = try await GitService.run(["worktree", "add", "-q", linkedMain.path, "main"], at: local.path)
        let linkedMainBranch = await GitBranchProtection.report(at: linkedMain.path, checkedOutElsewhere: []).branch
        try require(linkedMainBranch == .protected("main", .defaultBranch), "main is the default branch of a local-only repository with packed refs")
        let linkedFeature = root.appendingPathComponent("cleanup-local-feature")
        _ = try await GitService.run(["worktree", "add", "-q", "-f", linkedFeature.path, "feature"], at: local.path)
        let linkedFeatureBranch = await GitBranchProtection.report(at: linkedFeature.path, checkedOutElsewhere: []).branch
        try require(linkedFeatureBranch == .protected("feature", .checkedOutElsewhere), "The branch of the primary folder is protected")
        let topic = try await GitService.createWorktree(project: localProject, branch: "topic", root: root)
        let topicBranch = await GitBranchProtection.report(at: topic.path, checkedOutElsewhere: []).branch
        try require(topicBranch == .deletable("topic"), "Git reports a topic branch as deletable")
        _ = try await GitService.run(["checkout", "-q", "--detach"], at: topic.path)
        let detachedTopic = await GitBranchProtection.report(at: topic.path, checkedOutElsewhere: []).branch
        try require(detachedTopic == WorktreeBranch.none, "Git reports no branch for a detached worktree")
        try require(DefaultBranch.names(remoteHeads: ["develop"]) == ["main", "master", "develop"], "main, master and remote HEADs are default branches")
        let reftable = local.appendingPathComponent(".git/reftable")
        try FileManager.default.createDirectory(at: reftable, withIntermediateDirectories: true)
        let reftableBranch = await GitBranchProtection.report(at: topic.path, checkedOutElsewhere: [])
        let reftableCandidates = GitRepository.containing(topic.path).flatMap { GitBranchProtection.mergeCandidates(of: $0, remoteNames: []) }
        try require(reftableBranch == .unreadable && reftableCandidates == nil,
                    "A repository whose references aren't stored in files is never judged, so its branch is never deleted")
        try FileManager.default.removeItem(at: reftable)
        try require(BranchCleanup.unchecked.failure != nil && BranchCleanup.unchecked.branch == nil && !BranchCleanup.unchecked.isDeleted,
                    "A branch that couldn't be checked is reported as kept")
        print("PASS branch deletion with a worktree: merged, unmerged, forced, default and detached")
        try await defaultBranchMergeTests(root: root)
    }

    static func defaultBranchMergeTests(root: URL) async throws {
        let heads = DefaultBranch.remoteHeads(in: "refs/remotes/origin/HEAD\trefs/remotes/origin/develop\nrefs/remotes/gh/team/HEAD\trefs/remotes/gh/team/trunk\nrefs/remotes/fork/HEAD\t")
        try require(heads == [DefaultBranch.RemoteHead(name: "develop", reference: "refs/remotes/origin/develop"),
                              DefaultBranch.RemoteHead(name: "trunk", reference: "refs/remotes/gh/team/trunk")],
                    "Remote HEADs name their default branch, even when the remote name has a slash")
        let listed = GitService.worktreeEntries(in: "worktree /nonexistent/main\0HEAD 1234\0branch refs/heads/main\0\0worktree /nonexistent/bare\0bare\0\0"
                                                    + "worktree /nonexistent/detached\0HEAD 5678\0detached\0\0worktree /nonexistent/feature\0branch refs/heads/feature/x\0\0")
        try require(listed == [GitWorktreeEntry(path: "/nonexistent/main", branch: "main"), GitWorktreeEntry(path: "/nonexistent/bare"),
                               GitWorktreeEntry(path: "/nonexistent/detached"), GitWorktreeEntry(path: "/nonexistent/feature", branch: "feature/x")],
                    "The worktree list keeps each worktree with its branch, if any")
        let candidates = DefaultBranch.references(remoteHeads: [DefaultBranch.RemoteHead(name: "main", reference: "refs/remotes/origin/main")])
        try require(candidates == ["refs/remotes/origin/main", "refs/heads/main", "refs/heads/master", "refs/remotes/origin/master"],
                    "Default branch candidates are remote HEADs, then local and origin main or master")
        try require(DefaultBranch.references(remoteHeads: heads.reversed()).prefix(4)
                        == ["refs/remotes/origin/develop", "refs/remotes/gh/team/trunk", "refs/heads/develop", "refs/heads/trunk"],
                    "origin's HEAD comes first, then other remotes' HEADs and their local branches")
        let others = [DefaultBranch.RemoteHead(name: "b", reference: "refs/remotes/zeta/b"), DefaultBranch.RemoteHead(name: "a", reference: "refs/remotes/alpha/a")]
        try require(DefaultBranch.references(remoteHeads: others) == DefaultBranch.references(remoteHeads: others.reversed())
                        && DefaultBranch.references(remoteHeads: []) == ["refs/heads/main", "refs/heads/master", "refs/remotes/origin/main", "refs/remotes/origin/master"],
                    "Remote HEADs other than origin's are ordered by name, whatever order Git lists them in")
        let targets = DefaultBranch.mergeTargets(in: """
        refs/heads/main\trefs/remotes/origin/main\t
        refs/heads/main/old\t\t
        refs/heads/master\trefs/remotes/origin/master\t[gone]
        refs/remotes/origin/main
        """, candidates: candidates)
        try require(targets == ["refs/heads/main", "refs/remotes/origin/main", "refs/heads/master"],
                    "Merge targets are the default branches and their existing upstreams, without similarly named branches")

        let remote = root.appendingPathComponent("merge-remote.git")
        let local = root.appendingPathComponent("merge-local")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "--bare", "-b", "main", remote.path], at: root.path)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: local.path)
        try await commit("Initial", at: local.path)
        _ = try await GitService.run(["remote", "add", "origin", remote.path], at: local.path)
        _ = try await GitService.run(["push", "-q", "-u", "origin", "main"], at: local.path)
        let project = Project(url: local)

        let pushed = try await GitService.createWorktree(project: project, branch: "merge/pushed", root: root)
        try await commit("Pushed work", at: pushed.path)
        _ = try await GitService.run(["push", "-q", "-u", "origin", "merge/pushed"], at: pushed.path)
        try await GitService.removeWorktree(project: project, path: pushed.path)
        do {
            try await deleteBranch("merge/pushed", .merged, project: project)
            throw WorkspaceError(message: "FAIL: pushed but unmerged branch deleted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("isn’t fully merged") && error.message.contains("git branch -D merge/pushed"),
                        "A branch merged only into its own upstream is refused")
        }
        let pushedLeft = try await GitService.run(["branch", "--list", "merge/pushed"], at: local.path)
        try require(!pushedLeft.isEmpty, "A pushed but unmerged branch is kept")

        _ = try await GitService.run(["checkout", "-q", "-b", "elsewhere"], at: local.path)
        try await commit("Other work", at: local.path)
        let landed = try await GitService.createWorktree(project: project, branch: "merge/landed", root: root)
        _ = try await GitService.run(["reset", "-q", "--hard", "main"], at: landed.path)
        try await commit("Landed work", at: landed.path)
        _ = try await GitService.run(["branch", "-f", "main", "merge/landed"], at: local.path)
        try await GitService.removeWorktree(project: project, path: landed.path)
        try await deleteBranch("merge/landed", .merged, project: project)
        let landedLeft = try await GitService.run(["branch", "--list", "merge/landed"], at: local.path)
        try require(landedLeft.isEmpty, "A branch merged into main is deleted while the main folder is on another branch")

        let upstreamOnly = try await GitService.createWorktree(project: project, branch: "merge/upstream", root: root)
        _ = try await GitService.run(["reset", "-q", "--hard", "main"], at: upstreamOnly.path)
        try await commit("Merged on the server", at: upstreamOnly.path)
        _ = try await GitService.run(["push", "-q", "origin", "merge/upstream:main"], at: upstreamOnly.path)
        try await GitService.removeWorktree(project: project, path: upstreamOnly.path)
        try await deleteBranch("merge/upstream", .merged, project: project)
        let upstreamLeft = try await GitService.run(["branch", "--list", "merge/upstream"], at: local.path)
        try require(upstreamLeft.isEmpty, "A branch merged into the remote main branch is deleted before the local main is updated")

        try await deleteBranch("merge/pushed", .force, project: project)
        let forcedLeft = try await GitService.run(["branch", "--list", "merge/pushed"], at: local.path)
        try require(forcedLeft.isEmpty, "Forcing deletes a pushed but unmerged branch")

        let trunk = root.appendingPathComponent("merge-trunk")
        try FileManager.default.createDirectory(at: trunk, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "trunk"], at: trunk.path)
        try await commit("Initial", at: trunk.path)
        _ = try await GitService.run(["branch", "topic"], at: trunk.path)
        do {
            try await deleteBranch("topic", .merged, project: Project(url: trunk))
            throw WorkspaceError(message: "FAIL: branch deleted without a known main branch")
        } catch let error as WorkspaceError {
            try require(error.message.contains("main branch couldn’t be found") && error.message.contains("git branch -D topic"),
                        "Without a known main branch, a branch is never considered merged")
        }
        let topicLeft = try await GitService.run(["branch", "--list", "topic"], at: trunk.path)
        try require(!topicLeft.isEmpty, "A branch is kept when the main branch is unknown")
        print("PASS merged means merged into the repository's main branch")
    }

    private static func deleteBranch(_ branch: String, _ removal: BranchRemoval, project: Project) async throws {
        let candidates = GitRepository.containing(project.path).flatMap { GitBranchProtection.mergeCandidates(of: $0, remoteNames: []) } ?? []
        try await GitService.deleteBranch(branch, removal, mergingInto: candidates, project: project)
    }

    private static func commit(_ message: String, at path: String) async throws {
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", message], at: path)
    }

    static func agentProcessTests(root: URL) async throws {
        let rolloutID = "01a17eea-ca62-7da2-ab9b-4fe86e40d6a3"
        try require(AgentProcess.codexSessionID(inRolloutPath: "/h/sessions/2026/10/27/rollout-2026-10-27T20-51-18-\(rolloutID).jsonl") == rolloutID
                    && AgentProcess.codexSessionID(inRolloutPath: "/h/sessions/notes.jsonl") == nil, "Read Codex session IDs from rollout paths")
        try require(AgentProcess.copilotSessionID(inPath: "/Users/me/.copilot/session-state/abc/events.jsonl") == "abc", "Read Copilot session IDs")
        try require(AgentProcess.copilotJournalPath(inPath: "/Volumes/Work/.copilot/session-state/abc/workspace.yaml") == "/Volumes/Work/.copilot/session-state/abc/events.jsonl",
                    "Follow the Copilot journal next to the file the agent opened")
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
            detected = AgentProcess.find(under: shell.processIdentifier, fallbackDirectory: "/", claudeConfig: fakeHome.appendingPathComponent(".claude"))
            if detected != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let detected else { throw WorkspaceError(message: "FAIL: agent child process not found") }
        try require(detected.agent == .claude && detected.directory == WorkspacePath.canonical(root) && detected.sessionID == nil, "Find an agent child process and its directory")
        let childPID = agentChild(of: shell.processIdentifier)
        try #"{"pid":\#(childPID),"sessionId":"session-42"}"#.write(to: fakeHome.appendingPathComponent(".claude/sessions/\(childPID).json"), atomically: true, encoding: .utf8)
        let withSession = AgentProcess.find(under: shell.processIdentifier, fallbackDirectory: "/", claudeConfig: fakeHome.appendingPathComponent(".claude"))
        try require(withSession?.sessionID == "session-42" && withSession?.transcriptPath == nil, "Read the Claude session of the agent process")
        let sessionID = UUID().uuidString
        try #"{"pid":\#(childPID),"sessionId":"\#(sessionID)","cwd":"/Users/me/My Project"}"#.write(to: fakeHome.appendingPathComponent(".claude/sessions/\(childPID).json"), atomically: true, encoding: .utf8)
        let withTranscript = AgentProcess.find(under: shell.processIdentifier, fallbackDirectory: "/", claudeConfig: fakeHome.appendingPathComponent(".claude"))
        try require(withTranscript?.transcriptPath == fakeHome.appendingPathComponent(".claude/projects/-Users-me-My-Project/\(sessionID).jsonl").path,
                    "Locate the Claude transcript of the agent session")
        let customConfig = root.appendingPathComponent("custom-claude-config")
        try FileManager.default.createDirectory(at: customConfig.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let thirdPartyBin = root.appendingPathComponent("third-party-bin")
        try FileManager.default.createDirectory(at: thirdPartyBin, withIntermediateDirectories: true)
        let thirdPartyClaude = thirdPartyBin.appendingPathComponent("claude")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: thirdPartyClaude)
        let signing = Process()
        signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signing.arguments = ["--force", "--sign", "-", thirdPartyClaude.path]
        try signing.run()
        signing.waitUntilExit()
        let customShell = Process()
        customShell.executableURL = URL(fileURLWithPath: "/bin/sh")
        customShell.arguments = ["-c", "\"$0\" 10; true", thirdPartyClaude.path]
        customShell.currentDirectoryURL = root
        customShell.environment = ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": customConfig.path]
        try customShell.run()
        defer { customShell.terminate() }
        var customChild: Int32 = 0
        for _ in 0..<50 where customChild == 0 {
            customChild = agentChild(of: customShell.processIdentifier)
            if customChild == 0 { try await Task.sleep(for: .milliseconds(50)) }
        }
        try #"{"pid":\#(customChild),"sessionId":"custom-session"}"#.write(to: customConfig.appendingPathComponent("sessions/\(customChild).json"), atomically: true, encoding: .utf8)
        let custom = AgentProcess.find(under: customShell.processIdentifier, fallbackDirectory: "/", claudeConfig: fakeHome.appendingPathComponent(".claude"))
        try require(custom?.sessionID == "custom-session", "The CLAUDE_CONFIG_DIR of the running Claude process locates its session")
        let launched = Date()
        let attached = AgentProcess(agent: .claude, startedAt: launched, directory: "/p", sessionID: "s", transcriptPath: "/p/s.jsonl")
        let missedRead = AgentProcess(agent: .claude, startedAt: launched, directory: "/p", sessionID: nil).keepingTranscript(of: attached)
        try require(missedRead.transcriptPath == "/p/s.jsonl" && missedRead.sessionID == "s", "A missed session read keeps the attached journal")
        let cleared = AgentProcess(agent: .claude, startedAt: launched, directory: "/p", sessionID: "other").keepingTranscript(of: attached)
        try require(cleared.transcriptPath == nil, "A new session does not inherit the previous journal")
        print("PASS agent process detection and conversation titles")

        let now = Date()
        try require(AgentStatus(claudeStatus: "busy") == .working && AgentStatus(claudeStatus: "shell") == .working
                    && AgentStatus(claudeStatus: "idle") == .ready && AgentStatus(claudeStatus: "waiting") == .waitingForInput
                    && AgentStatus(claudeStatus: "unknown") == nil, "Map Claude session statuses")
        try require(AgentStatus(screen: ["  Would you like to run the following command?", "› 1. Yes, proceed"], lastOutput: now, now: now) == .waitingForInput,
                    "An approval prompt on screen means the agent waits for input")
        try require(AgentStatus(screen: ["• Working (3s • esc to interrupt)"], lastOutput: now.addingTimeInterval(-0.5), now: now) == .working,
                    "Recent output means the agent is working")
        try require(AgentStatus(screen: ["› Ask Codex to do anything"], lastOutput: now.addingTimeInterval(-10), now: now) == .ready,
                    "A quiet agent without prompt is ready")
        print("PASS agent status")

        let fm = FileManager.default
        let sessionJournal = root.appendingPathComponent("claude/session.jsonl")
        let subagents = sessionJournal.deletingPathExtension().appendingPathComponent("subagents")
        try fm.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data().write(to: sessionJournal)
        let runStart = Date().addingTimeInterval(-60)
        func spawn(_ id: String, metadata: String?, modified: Date, journal content: String = "{}\n") throws {
            let journal = subagents.appendingPathComponent("agent-\(id).jsonl")
            try Data(content.utf8).write(to: journal)
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: journal.path)
            if let metadata { try Data(metadata.utf8).write(to: subagents.appendingPathComponent("agent-\(id).meta.json")) }
        }
        try spawn("old", metadata: #"{"description":"Previous run"}"#, modified: runStart.addingTimeInterval(-10))
        try spawn("running", metadata: #"{"description":"Explore the sidebar","agentType":"Explore"}"#, modified: Date())
        try spawn("done", metadata: #"{"description":"  ","name":"code-review","finished":true}"#, modified: Date())
        try spawn("stale", metadata: #"{"description":"Long finished","finished":true}"#, modified: runStart.addingTimeInterval(1))
        try spawn("stopped", metadata: #"{"description":"Cancelled","stoppedByUser":true,"finished":true}"#, modified: Date())
        try spawn("bare", metadata: nil, modified: Date())
        try spawn("answered", metadata: #"{"description":"Legacy background agent"}"#, modified: Date(),
                  journal: #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"# + "\n" + #"{"type":"user","message":{}}"# + "\n"
                    + #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"# + "\n" + #"{"type":"attachment"}"# + "\n")
        try Data("{}".utf8).write(to: subagents.appendingPathComponent("agent-running.forked-skill.json"))
        let process = AgentProcess(agent: .claude, startedAt: runStart, directory: root.path, sessionID: "session", transcriptPath: sessionJournal.path)
        let catalog = ClaudeSubagents()
        let listed = Dictionary(uniqueKeysWithValues: await catalog.list(of: process, now: runStart.addingTimeInterval(ClaudeSubagents.finishedVisibility + 30))
            .map { ($0.journal.lastPathComponent, $0) })
        try require(Set(listed.keys) == ["agent-running.jsonl", "agent-done.jsonl", "agent-stale.jsonl", "agent-stopped.jsonl", "agent-bare.jsonl", "agent-answered.jsonl"],
                    "List the subagents of the current run only")
        try require(listed["agent-running.jsonl"]?.title == "Explore the sidebar" && listed["agent-running.jsonl"]?.status == .working
                    && listed["agent-done.jsonl"]?.title == "code-review" && listed["agent-done.jsonl"]?.status == .done
                    && listed["agent-stopped.jsonl"]?.status == .stopped && listed["agent-bare.jsonl"]?.status == .working
                    && listed["agent-answered.jsonl"]?.status == .done,
                    "Read subagent titles and statuses from their metadata")
        try require(listed["agent-done.jsonl"]?.isVisible == true && listed["agent-stale.jsonl"]?.isVisible == false
                    && listed["agent-running.jsonl"]?.isVisible == true, "Finished subagents leave the sidebar after a while, running ones stay")
        let abandoned = await catalog.list(of: process, now: Date().addingTimeInterval(ClaudeSubagents.abandonment + 60))
        try require(abandoned.first { $0.journal.lastPathComponent == "agent-bare.jsonl" }?.status == .stopped
                    && abandoned.allSatisfy { !$0.isVisible }, "A silent unfinished subagent is eventually treated as stopped")
        let fresh = await ClaudeSubagents().list(of: process).map(\.id)
        let cached = await catalog.list(of: process).map(\.id)
        try require(cached == fresh
                    && Set(listed.values.map(\.id)).count == listed.count, "Subagent identifiers are stable and distinct")
        let runningMetadata = subagents.appendingPathComponent("agent-running.meta.json")
        try Data(#"{"description":"Explore the sidebar","finished":true}"#.utf8).write(to: runningMetadata)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: runningMetadata.path)
        let updated = await catalog.list(of: process)
        try require(updated.first { $0.journal.lastPathComponent == "agent-running.jsonl" }?.status == .done,
                    "Cached subagents pick up metadata changes")
        let codex = AgentProcess(agent: .codex, startedAt: runStart, directory: root.path, sessionID: "session", transcriptPath: sessionJournal.path)
        let codexSubagents = await catalog.list(of: codex)
        try require(codexSubagents.isEmpty, "Only Claude sessions have subagent journals")
        let longDirectory = root.appendingPathComponent("claude/long/subagents")
        try fm.createDirectory(at: longDirectory, withIntermediateDirectories: true)
        let report = String(repeating: "x", count: 200_000)
        let longJournal = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"# + "\n"
            + #"{"type":"assistant","message":{"stop_reason":"end_turn","content":""# + report + #""}}"# + "\n"
        try Data(longJournal.utf8).write(to: longDirectory.appendingPathComponent("agent-long.jsonl"))
        let long = await catalog.list(in: longDirectory, since: runStart)
        try require(long.first?.status == .done, "A final answer longer than the read window still ends the subagent")
        print("PASS Claude subagents")
    }

    static func terminalLayoutTests() throws {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let pair = TerminalLayout.split(.horizontal, [.terminal(a), .terminal(b)])
        try require(DropEdge(location: CGPoint(x: 10, y: 50), in: CGSize(width: 200, height: 100)) == .leading
                    && DropEdge(location: CGPoint(x: 190, y: 50), in: CGSize(width: 200, height: 100)) == .trailing
                    && DropEdge(location: CGPoint(x: 100, y: 5), in: CGSize(width: 200, height: 100)) == .top
                    && DropEdge(location: CGPoint(x: 100, y: 95), in: CGSize(width: 200, height: 100)) == .bottom
                    && DropEdge(location: CGPoint(x: 100, y: 400), in: CGSize(width: 200, height: 100)) == .bottom
                    && DropEdge(location: .zero, in: .zero) == .trailing, "Map a drop location to the nearest pane edge")
        try require(DropEdge.leading.axis == .horizontal && DropEdge.bottom.axis == .vertical
                    && DropEdge.leading.insertsBefore && DropEdge.top.insertsBefore && !DropEdge.trailing.insertsBefore,
                    "Drop edges carry their split axis and side")
        try require(TerminalLayout.terminal(a).inserting(b, beside: a, edge: .leading) == .split(.horizontal, [.terminal(b), .terminal(a)])
                    && TerminalLayout.terminal(a).inserting(b, beside: a, edge: .bottom) == .split(.vertical, [.terminal(a), .terminal(b)]),
                    "Insert before or after a single pane")
        try require(pair.inserting(c, beside: a, edge: .trailing) == .split(.horizontal, [.terminal(a), .terminal(c), .terminal(b)])
                    && pair.inserting(c, beside: b, edge: .leading) == .split(.horizontal, [.terminal(a), .terminal(c), .terminal(b)])
                    && pair.inserting(c, beside: a, edge: .leading) == .split(.horizontal, [.terminal(c), .terminal(a), .terminal(b)]),
                    "Insert along the same axis without nesting")
        try require(pair.inserting(c, beside: b, edge: .top) == .split(.horizontal, [.terminal(a), .split(.vertical, [.terminal(c), .terminal(b)])]),
                    "Insert across the axis nests a split around the target")
        try require(pair.inserting(c, beside: d, edge: .top) == pair && pair.inserting(a, beside: b, edge: .top) == pair
                    && pair.inserting(a, beside: a, edge: .top) == pair, "Insert ignores unknown targets, present terminals and itself")
        try require(pair.moving(a, beside: a, edge: .trailing) == pair && TerminalLayout.terminal(a).moving(a, beside: a, edge: .top) == .terminal(a),
                    "Dropping a pane on itself changes nothing")
        try require(pair.moving(a, beside: b, edge: .trailing) == .split(.horizontal, [.terminal(b), .terminal(a)])
                    && pair.moving(b, beside: a, edge: .trailing) == pair,
                    "Move a pane within the same split")
        try require(pair.moving(a, beside: b, edge: .bottom) == .split(.vertical, [.terminal(b), .terminal(a)]),
                    "Moving across the axis collapses the emptied split")
        let nested = TerminalLayout.split(.horizontal, [.terminal(a), .split(.vertical, [.terminal(b), .split(.horizontal, [.terminal(c), .terminal(d)])])])
        try require(nested.removing(b) == .split(.horizontal, [.terminal(a), .terminal(c), .terminal(d)]),
                    "Removing a pane flattens same-axis nesting")
        try require(nested.moving(b, beside: a, edge: .leading) == .split(.horizontal, [.terminal(b), .terminal(a), .terminal(c), .terminal(d)]),
                    "Moving keeps the layout normalised")
        try require(nested.moving(d, beside: b, edge: .bottom) == .split(.horizontal, [.terminal(a), .split(.vertical, [.terminal(b), .terminal(d), .terminal(c)])]),
                    "Moving out of a nested split collapses it into its parent")
        try require(pair.moving(c, beside: a, edge: .top) == .split(.horizontal, [.split(.vertical, [.terminal(c), .terminal(a)]), .terminal(b)]),
                    "Moving a terminal from elsewhere inserts it")
        print("PASS terminal layout drops")
    }

    static func homeAbbreviationTests() throws {
        let home = NSHomeDirectory()
        try require(home.abbreviatingHome == "~" && (home + "/").abbreviatingHome == "~" && (home + "/Projects/App").abbreviatingHome == "~/Projects/App",
                    "Abbreviate the home folder and paths inside it")
        try require((home + "y").abbreviatingHome == home + "y" && (home + "y/App").abbreviatingHome == home + "y/App",
                    "Keep a sibling folder that only shares the home prefix")
        try require(("/Volumes/Backup" + home).abbreviatingHome == "/Volumes/Backup" + home && "/tmp/App".abbreviatingHome == "/tmp/App",
                    "Keep the home path when it appears after the start")
        print("PASS home folder abbreviation")
    }

    static func agentChild(of pid: Int32) -> Int32 {
        var buffer = [Int32](repeating: 0, count: 16)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(buffer.count * 4))
        return bytes > 0 ? buffer[0] : 0
    }
}

private extension Optional {
    func unwrapped() throws -> Wrapped {
        guard let self else { throw WorkspaceError(message: "FAIL: unexpected nil") }
        return self
    }
}
