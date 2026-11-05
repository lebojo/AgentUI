import Foundation
import Observation

// This test executable compiles the production store with inert terminal processes.
// Real SwiftTerm and PTY behavior is covered by integration.py against the actual app.
@MainActor final class TerminalSessions {
    func close(_ id: UUID) {}
    func start(_ context: TerminalContext, command: [String] = []) {}
    func isRunning(_ id: UUID) -> Bool { true }
    weak var delegate: TerminalSessionsDelegate?
    func agentResumes() -> [UUID: AgentResume?] { [:] }
    func subagent(_ id: UUID?) -> SubagentSelection? { nil }
    var branchesByPath: [String: GitBranch] = [:]
    var agentStatuses: [UUID: AgentStatus] = [:]
    var runningAgents: [UUID: ConversationAgent] = [:]

    func readBranches(of projects: [Project]) {
        let repositories = projects.flatMap(\.worktrees).map(\.path).compactMap { path in GitRepository.containing(path).map { (path, $0.branch) } }
        branchesByPath = Dictionary(repositories, uniquingKeysWith: { first, _ in first })
    }
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func mark() { lock.lock(); changed = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return changed }
}

@MainActor private func planned(_ url: URL, in store: WorkspaceStore, into folderID: UUID) async throws -> RepositoryImport? {
    await store.importFolder(url, into: folderID)
    defer { store.pendingImport = nil }
    return store.pendingImport
}

@main struct StoreTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw WorkspaceError(message: "FAIL: " + message) }
    }
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("agentui-store-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let folder = ProjectFolder(name: "Studio")
        let p1 = Project(url: root.appendingPathComponent("one"), folderID: folder.id)
        let p2 = Project(url: root.appendingPathComponent("two"))
        let initial = Workspace(folders: [folder], projects: [p1, p2])
        try WorkspaceDisk.save(initial, to: file)
        let store = WorkspaceStore(fileURL: file)
        let projectsChanged = ChangeFlag(), foldersChanged = ChangeFlag()
        withObservationTracking { _ = store.projects } onChange: { projectsChanged.mark() }
        withObservationTracking { _ = store.folders } onChange: { foldersChanged.mark() }
        for i in 0..<100 {
            store.selection = (i.isMultiple(of: 2) ? p1 : p2).worktrees[0].terminals[0].id
            store.setExpanded(p1.id, i.isMultiple(of: 2))
        }
        try require(!projectsChanged.value && !foldersChanged.value, "Selection and disclosure do not invalidate project/folder readers")
        let beforeFlush = try WorkspaceDisk.load(from: file)
        try require(beforeFlush == initial, "Rapid UI changes do not synchronously rewrite disk")
        try await store.flushPersistence()
        let afterFlush = try WorkspaceDisk.load(from: file)
        try require(afterFlush == store.state && !store.hasUnsavedChanges, "Flush persists the final coalesced state")
        store.selection = p1.worktrees[0].terminals[0].id
        try require(store.hasUnsavedChanges, "Selecting another terminal is saved")
        try await store.flushPersistence()
        let reselected = try WorkspaceDisk.load(from: file)
        try require(reselected.selection == p1.worktrees[0].terminals[0].id, "The new selection reaches disk")
        print("PASS granular observation, coalescing and explicit durable flush")

        store.busyProjects.insert(p2.id)
        try require(store.isBusy(.project(p2.id)) && !store.isBusy(.terminal(p2.worktrees[0].terminals[0].id)), "Only removals inside a busy project are blocked")
        store.remove(.project(p2.id))
        try require(store.projects.contains { $0.id == p2.id } && store.errorMessage != nil, "Removing a busy project is refused with an error")
        store.busyProjects.remove(p2.id)
        store.errorMessage = nil
        print("PASS busy project removal")

        if geteuid() != 0 {
            try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            _ = store.addFolder("Pending save")
            do { try await store.flushPersistence(); throw WorkspaceError(message: "FAIL: save failure swallowed") }
            catch let error as WorkspaceError { try require(!error.message.hasPrefix("FAIL"), "Persistence error reaches caller") }
            try require(store.hasUnsavedChanges && store.persistenceError != nil, "Unsaved state remains explicit after failure")
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try await store.flushPersistence()
            let recovered = try WorkspaceDisk.load(from: file)
            try require(recovered == store.state && !store.hasUnsavedChanges && store.persistenceError == nil, "Retry persists pending modifications without replaying mutations")
            print("PASS save error propagation and retry")
        }
        let all = SidebarFilterInput(folders: [folder], projects: [p1, p2], query: "").filtered()
        let byFolderName = SidebarFilterInput(folders: [folder], projects: [p1, p2], query: "Studio").filtered()
        let byProjectName = SidebarFilterInput(folders: [folder], projects: [p1, p2], query: "two").filtered()
        try require(all.groups[0].projects == [p1] && all.ungrouped == [p2], "Preserve grouped and ungrouped projects")
        try require(byFolderName.groups[0].projects == [p1] && byFolderName.ungrouped.isEmpty, "Folder search reveals its projects")
        try require(byProjectName.groups.isEmpty && byProjectName.ungrouped == [p2], "Filter projects without inventing empty groups")
        print("PASS sidebar filtering and stable identities")

        let nestedFile = root.appendingPathComponent("nested.json")
        let nested = WorkspaceStore(fileURL: nestedFile)
        let parent = nested.addFolder("Clients")
        let child = nested.addFolder("Acme", parentID: parent)
        let grandchild = nested.addFolder("Mobile", parentID: child)
        let orphanParent = nested.addFolder("Ignoré", parentID: UUID())
        try require(nested.folders.first { $0.id == orphanParent }?.parentID == nil, "Unknown parents create root folders")
        try require(!nested.canMoveFolder(parent, to: grandchild) && !nested.canMoveFolder(parent, to: parent), "Folders cannot move into their own subtree")
        nested.moveFolder(parent, to: grandchild)
        try require(nested.folders.first { $0.id == parent }?.parentID == nil, "Refused moves leave the hierarchy intact")
        try require(nested.folders.destinations(excluding: child).map(\.title) == ["Clients", "Ignoré"], "Destinations exclude the moved subtree")
        try require(nested.folders.destinations().map(\.title).contains("Clients › Acme › Mobile"), "Destinations show nested paths")
        let nestedProject = Project(url: root.appendingPathComponent("one"), folderID: grandchild)
        let tree = SidebarFilterInput(folders: nested.folders, projects: [nestedProject], query: "").filtered()
        try require(tree.groups.map(\.folder.name) == ["Clients", "Ignoré"] && tree.groups[0].total == 1, "Nested folders render under their parent and count descendants")
        try require(tree.groups[0].subgroups[0].subgroups[0].projects == [nestedProject], "Projects appear in their nested folder")
        let byParentName = SidebarFilterInput(folders: nested.folders, projects: [nestedProject], query: "Clients").filtered()
        try require(byParentName.groups.count == 1 && byParentName.groups[0].subgroups[0].subgroups[0].showsAll, "Matching a parent reveals its whole subtree")
        let byProject = SidebarFilterInput(folders: nested.folders, projects: [nestedProject], query: "one").filtered()
        try require(byProject.groups.map(\.folder.name) == ["Clients"] && byProject.groups[0].subgroups[0].projects.isEmpty, "Filtering keeps only the path to matching projects")
        nested.setExpanded(parent, false)
        try require(nested.drop(grandchild, into: orphanParent) && nested.isExpanded(orphanParent), "Dropping a folder moves and reveals it")
        nested.setAppearance(SidebarAppearance(kind: .folder, symbol: .hammer, tint: .orange), for: child)
        try require(nested.appearance(of: child) == SidebarAppearance(kind: .folder, symbol: .hammer, tint: .orange), "Folders keep a custom appearance")
        nested.removeFolder(child)
        try require(nested.folders.allSatisfy { $0.parentID != child }, "Dissolving a folder hands its subfolders to its parent")
        try await nested.flushPersistence()
        let reloaded = try WorkspaceDisk.load(from: nestedFile)
        try require(reloaded.folders == nested.folders, "Nested folders and appearances persist")
        print("PASS nested folders and appearance")

        struct Item: Identifiable, Equatable { let id: Int }
        let items = (1...6).map(Item.init)
        try require(items.moving([1, 2, 3], from: [2], to: 0)?.map(\.id) == [3, 1, 2, 4, 5, 6], "Moving up keeps the others in order")
        try require(items.moving([1, 2, 3], from: [0], to: 3)?.map(\.id) == [2, 3, 1, 4, 5, 6], "Moving to the end stays after the last visible sibling")
        try require(items.moving([2, 4, 6], from: [2], to: 1)?.map(\.id) == [1, 2, 3, 6, 4, 5], "Moving among a subset keeps hidden elements in place")
        try require(items.moving([2, 4, 6], from: [0, 1], to: 3)?.map(\.id) == [1, 3, 5, 6, 2, 4], "Several siblings move together")
        try require(items.moving([1, 2], from: [5], to: 0) == nil, "Invalid indices change nothing")
        try require(items.moving([3], from: [0], to: 1) == nil && items.moving([2, 4], from: [0, 1], to: 0) == nil,
                    "Dropping every visible sibling in place leaves hidden ones untouched")
        try require(items.moving([1, 2, 3], from: [1], to: 1) == nil, "Dropping in place reports no change")

        let orderedRoot = root.appendingPathComponent("ordered")
        let orderedURLs = ["alpha", "beta", "gamma"].map { orderedRoot.appendingPathComponent($0) }
        for url in orderedURLs { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        let orderedFile = root.appendingPathComponent("ordered.json")
        let ordered = WorkspaceStore(fileURL: orderedFile)
        let alpha = try ordered.addProject(orderedURLs[0]).id, beta = try ordered.addProject(orderedURLs[1]).id, gamma = try ordered.addProject(orderedURLs[2]).id
        ordered.reorderProjects([alpha, beta, gamma], from: [2], to: 0)
        try require(ordered.projects.map(\.id) == [gamma, alpha, beta], "Projects reorder")
        let folderOne = ordered.addFolder("Un"), folderTwo = ordered.addFolder("Deux"), inner = ordered.addFolder("Sous", parentID: folderOne)
        ordered.reorderFolders([folderOne, folderTwo], from: [1], to: 0)
        try require(ordered.folders.map(\.id) == [folderTwo, folderOne, inner], "Root folders reorder without touching subfolders")
        let alphaRecord = ordered.projects.first { $0.id == alpha }!
        let main = alphaRecord.worktrees[0]
        let second = try ordered.addTerminal(projectID: alpha, worktreeID: main.id, select: false)
        let orderedWorktree = ordered.projects.first { $0.id == alpha }!.worktrees[0]
        let orderedBlocks = orderedWorktree.terminalBlocks(showing: orderedWorktree.terminals)
        ordered.reorderTerminalBlocks(in: main.id, orderedBlocks, from: [orderedBlocks.count - 1], to: 0)
        try require(ordered.projects.first { $0.id == alpha }!.worktrees[0].terminals.first?.id == second.terminal.id, "Terminals reorder inside their worktree")
        ordered.moveProject(alpha, to: folderOne)
        ordered.moveProject(gamma, to: folderOne)
        try require(ordered.projects.filter { $0.folderID == folderOne }.map(\.id) == [alpha, gamma], "A project moved into a folder lands last in it")
        ordered.moveProject(alpha, to: nil)
        ordered.moveProject(gamma, to: nil)
        ordered.reorderProjects([beta, alpha, gamma], from: [0], to: 3)
        ordered.reorderProjects([alpha, gamma, beta], from: [1], to: 0)
        let orderedTree = SidebarFilterInput(folders: ordered.folders, projects: ordered.projects, query: "").filtered()
        try require(orderedTree.groups.map(\.folder.name) == ["Deux", "Un"] && orderedTree.ungrouped.map(\.id) == [gamma, alpha, beta],
                    "The sidebar follows the new order")
        try await ordered.flushPersistence()
        let reloadedOrder = try WorkspaceDisk.load(from: orderedFile)
        try require(reloadedOrder == ordered.state, "The order persists")
        print("PASS sibling reordering")

        let splitFile = root.appendingPathComponent("split.json")
        let split = WorkspaceStore(fileURL: splitFile)
        let splitRoot = root.appendingPathComponent("split-project")
        try fm.createDirectory(at: splitRoot, withIntermediateDirectories: true)
        let splitProject = try split.addProject(splitRoot)
        let first = splitProject.worktrees[0].terminals[0].id
        let right = try split.splitTerminal(first, axis: .horizontal).terminal.id
        let below = try split.splitTerminal(right, axis: .vertical).terminal.id
        let third = try split.splitTerminal(below, axis: .vertical).terminal.id
        try require(split.layout(for: first) == .split(.horizontal, [.terminal(first), .split(.vertical, [.terminal(right), .terminal(below), .terminal(third)])]),
                    "Splitting nests panes and appends along the same axis")
        try require(split.selection == third && split.worktree(containing: third)?.terminals.count == 4, "Split panes are real terminals of the worktree")
        split.closeTerminal(third)
        try require(split.selection == below, "Closing a pane focuses its neighbour")
        split.closeTerminal(right)
        split.closeTerminal(below)
        try require(split.layout(for: first) == .terminal(first) && split.worktree(containing: first)?.layouts.isEmpty == true,
                    "A layout with a single pane disappears")
        print("PASS split terminal layouts")

        let dropped = splitProject.worktrees[0].id
        let pane2 = try split.addTerminal(projectID: splitProject.id, worktreeID: dropped).terminal.id
        let pane3 = try split.addTerminal(projectID: splitProject.id, worktreeID: dropped).terminal.id
        let pane4 = try split.addTerminal(projectID: splitProject.id, worktreeID: dropped, select: false).terminal.id
        try require(!split.moveTerminal(first, beside: first, edge: .trailing) && split.worktree(containing: first)?.layouts.isEmpty == true,
                    "Dropping a terminal on itself changes nothing")
        try require(split.moveTerminal(pane2, beside: first, edge: .trailing) && split.layout(for: first) == .split(.horizontal, [.terminal(first), .terminal(pane2)])
                    && split.selection == pane2, "Dropping a standalone terminal splits the target and selects it")
        try require(split.moveTerminal(pane3, beside: pane2, edge: .top)
                    && split.layout(for: first) == .split(.horizontal, [.terminal(first), .split(.vertical, [.terminal(pane3), .terminal(pane2)])]),
                    "Dropping on an edge inserts before the target")
        try require(split.moveTerminal(pane3, beside: first, edge: .leading)
                    && split.layout(for: first) == .split(.horizontal, [.terminal(pane3), .terminal(first), .terminal(pane2)]),
                    "Rearrange panes within a layout")
        let rearranged = split.projects
        try require(split.moveTerminal(pane3, beside: first, edge: .leading) && split.projects == rearranged && split.selection == pane3,
                    "Dropping a pane where it already is leaves the workspace untouched")
        _ = try split.splitTerminal(pane4, axis: .vertical)
        try require(split.worktree(containing: first)?.layouts.count == 2, "A worktree can hold several layouts")
        try require(split.moveTerminal(pane4, beside: pane2, edge: .bottom)
                    && split.layout(for: first) == .split(.horizontal, [.terminal(pane3), .terminal(first), .split(.vertical, [.terminal(pane2), .terminal(pane4)])])
                    && split.worktree(containing: first)?.layouts.count == 1 && split.selection == pane4,
                    "Moving from another layout of the worktree dissolves the emptied layout")
        let elsewhere = root.appendingPathComponent("dropped-elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let otherWorktree = try split.addProject(elsewhere)
        let foreign = otherWorktree.worktrees[0].terminals[0].id
        try require(!split.canMoveTerminal(foreign, beside: first) && !split.moveTerminal(foreign, beside: first, edge: .leading)
                    && split.layout(for: foreign) == .terminal(foreign), "Terminals of another worktree cannot be combined")
        let firstWorktree = split.worktree(containing: first)!.id, foreignWorktree = otherWorktree.worktrees[0].id
        try require(split.acceptsTerminalInsert(in: firstWorktree) && split.acceptsTerminalInsert(in: foreignWorktree),
                    "Without a known drag, every terminal list accepts a dropped terminal")
        split.beginDragging(first)
        try require(split.draggedTerminal == first && split.acceptsTerminalInsert(in: firstWorktree) && !split.acceptsTerminalInsert(in: foreignWorktree),
                    "Remember the dragged terminal, and only its own worktree's list accepts it")
        split.endDragging()
        try require(split.draggedTerminal == nil && split.acceptsTerminalInsert(in: foreignWorktree), "A drop forgets the dragged terminal")
        try await split.flushPersistence()
        let reloadedDrops = try WorkspaceDisk.load(from: splitFile)
        try require(reloadedDrops == split.state, "Dropped layouts persist")
        print("PASS drop terminals into layouts")

        do {
            let split = WorkspaceStore(fileURL: root.appendingPathComponent("blocks.json"))
            let blocksRoot = root.appendingPathComponent("blocks-project")
            try fm.createDirectory(at: blocksRoot, withIntermediateDirectories: true)
            let splitProject = try split.addProject(blocksRoot)
            let first = splitProject.worktrees[0].terminals[0].id
            let worktreeID = splitProject.worktrees[0].id
            let b = try split.addTerminal(projectID: splitProject.id, worktreeID: worktreeID, name: "b").terminal.id
            let c = try split.splitTerminal(b, axis: .horizontal).terminal.id
            let d = try split.addTerminal(projectID: splitProject.id, worktreeID: worktreeID, name: "d").terminal.id
            let e = try split.splitTerminal(first, axis: .vertical).terminal.id
            func blocks() -> [SidebarTerminalBlock] {
                let worktree = split.worktree(containing: first)!
                return worktree.terminalBlocks(showing: worktree.terminals)
            }
            try require(blocks().map { $0.terminals.map(\.id) } == [[first, e], [b, c], [d]], "Split panes form one sidebar block placed at their first terminal")
            try require(blocks().map(\.axis) == [.vertical, .horizontal, nil], "A block keeps its split axis")
            try require(blocks()[0].contains(e) && !blocks()[0].contains(b), "A block knows its terminals")
            try require(blocks()[0].selectionTag(for: e) == e && blocks()[0].selectionTag(for: d) == first && blocks()[0].singleTerminal == nil
                            && blocks()[0].selectedMember(e) == e && blocks()[0].selectedMember(d) == nil
                            && blocks()[2].singleTerminal?.id == d && blocks()[2].selectionTag(for: nil) == d,
                        "A split block is selected through its focused pane, a single row through its terminal")
            func moveBlocks(_ source: IndexSet, to destination: Int) {
                split.reorderTerminalBlocks(in: worktreeID, blocks(), from: source, to: destination)
            }
            moveBlocks([2], to: 0)
            try require(blocks().map { $0.terminals.map(\.id) } == [[d], [first, e], [b, c]], "A single terminal moves above a split block")
            moveBlocks([1], to: 3)
            try require(split.worktree(containing: first)?.terminals.map(\.id) == [d, b, c, first, e], "A split block moves as a whole")
            let filtered = split.worktree(containing: first)!.terminalBlocks(showing: split.worktree(containing: first)!.terminals.filter { [first, c, d].contains($0.id) })
            try require(filtered.map { $0.terminals.map(\.id) } == [[d], [c], [first]] && filtered.allSatisfy { !$0.isSplit && $0.axis == nil },
                        "A split whose other panes are filtered out shows as a single row")
            let leadingRoot = root.appendingPathComponent("blocks-leading")
            try fm.createDirectory(at: leadingRoot, withIntermediateDirectories: true)
            let leadingProject = try split.addProject(leadingRoot)
            let leadingWorktree = leadingProject.worktrees[0].id
            let paneA = leadingProject.worktrees[0].terminals[0].id
            let paneB = try split.addTerminal(projectID: leadingProject.id, worktreeID: leadingWorktree, name: "b").terminal.id
            let paneC = try split.addTerminal(projectID: leadingProject.id, worktreeID: leadingWorktree, name: "c").terminal.id
            try require(split.moveTerminal(paneC, beside: paneA, edge: .leading), "Drop a terminal before another one")
            func leadingBlocks() -> [[UUID]] {
                let worktree = split.worktree(containing: paneA)!
                return worktree.terminalBlocks(showing: worktree.terminals).map { $0.terminals.map(\.id) }
            }
            try require(leadingBlocks() == [[paneC, paneA], [paneB]], "A leading drop orders the block by its panes")
            let worktreeBlocks = split.worktree(containing: paneA)!
            split.reorderTerminalBlocks(in: leadingWorktree, worktreeBlocks.terminalBlocks(showing: worktreeBlocks.terminals), from: [1], to: 0)
            try require(leadingBlocks() == [[paneB], [paneC, paneA]], "A terminal moves above a block whose pane order differs from the terminal order")
            let terminals = split.worktree(containing: first)!.terminals
            try require(blocks().reordering(terminals, moving: c, to: 0)?.map(\.id) == [b, c, d, first, e],
                        "Inserting a split member moves its whole block")
            try require(blocks().reordering(terminals, moving: d, to: 3)?.map(\.id) == [b, c, first, e, d],
                        "Inserting a terminal after the last block moves it to the end")
            try require(blocks().reordering(terminals, moving: d, to: 1) == nil && blocks().reordering(terminals, moving: paneA, to: 0) == nil,
                        "Inserting at its own place or from another worktree changes nothing")
            split.insertTerminal(paneA, in: worktreeID, blocks(), at: 0)
            try require(split.worktree(containing: first)?.terminals.map(\.id) == [d, b, c, first, e],
                        "A terminal dragged from another worktree is not inserted")
            split.insertTerminal(e, in: worktreeID, blocks(), at: 0)
            try require(blocks().map { $0.terminals.map(\.id) } == [[first, e], [d], [b, c]],
                        "Dropping a dragged terminal between rows moves its block there")
            let dropped = await TerminalDragItem.terminalID(in: [TerminalDragItem(terminalID: e).itemProvider])
            let unrelated = await TerminalDragItem.terminalID(in: [NSItemProvider(object: "text" as NSString)])
            try require(dropped == e && unrelated == nil, "A drop reads the dragged terminal from its own payload")
            print("PASS sidebar split blocks")
        }

        var busy = Project(url: root.appendingPathComponent("busy"))
        let waiting = TerminalRecord(name: "Review")
        let working = TerminalRecord(name: "Build")
        let ready = TerminalRecord(name: "Docs")
        let shell = TerminalRecord(name: "Shell")
        busy.worktrees[0].terminals = [ready, shell, working]
        busy.worktrees.append(Worktree(name: "feature-x", path: root.appendingPathComponent("feature-x").path, terminals: [waiting]))
        let statuses: [UUID: AgentStatus] = [waiting.id: .waitingForInput, working.id: .working, ready.id: .ready]
        let progress = WorkInProgress.groups(in: [busy], statuses: statuses, agents: [working.id: .codex])
        try require(progress.map(\.status) == [.waitingForInput, .working, .ready], "Agents needing input come first, then working, then ready")
        try require(progress.flatMap(\.items).map(\.id) == [waiting.id, working.id, ready.id], "Only terminals running an agent are listed")
        try require(progress[0].items[0].location == "busy · feature-x" && progress[1].items[0].agent == .codex, "Items carry their project, worktree and agent")
        try require(WorkInProgress.groups(in: [busy], statuses: [:], agents: [:]).isEmpty, "No running agent hides the section")
        let searched = WorkInProgress.groups(WorkInProgress.groups(in: [busy], statuses: statuses, agents: [:]), matching: "feature")
        try require(searched.map(\.status) == [.waitingForInput] && searched[0].items.map(\.id) == [waiting.id], "The sidebar filter applies to work in progress")
        try require(WorkInProgress.groups(progress, matching: "") == progress, "An empty filter keeps every group")
        try require(progress.flatMap(\.rows).map(\.id) == [.status(.waitingForInput), .terminal(waiting.id), .status(.working), .terminal(working.id),
                                                          .status(.ready), .terminal(ready.id)]
                        && progress[0].rows.first == .status(.waitingForInput, count: 1),
                    "Work in progress flattens into one list of status headers and terminals with stable identities")
        let splitTerminal = split.projects[0].worktrees[0].terminals[0]
        let progressChanged = ChangeFlag()
        withObservationTracking { _ = split.workInProgress } onChange: { progressChanged.mark() }
        split.rename(splitTerminal.id, to: "Renamed")
        try require(!progressChanged.value && split.workInProgress.isEmpty, "Project edits without running agents leave work in progress untouched")
        split.sessions.agentStatuses = [splitTerminal.id: .working]
        split.sessions.runningAgents = [splitTerminal.id: .claude]
        split.terminalSessionsDidChangeAgents()
        try require(progressChanged.value && split.workInProgress.map(\.status) == [.working]
                        && split.workInProgress[0].items.map(\.name) == ["Renamed"] && split.workInProgress[0].items[0].agent == .claude,
                    "An agent status change updates the cached work in progress")
        split.rename(splitTerminal.id, to: "Renamed Again")
        try require(split.workInProgress[0].items.map(\.name) == ["Renamed Again"], "Renaming a terminal running an agent updates work in progress")
        var renamedProject = busy
        renamedProject.name = "elsewhere"
        var movedTerminal = busy
        movedTerminal.worktrees[1].terminals.append(movedTerminal.worktrees[0].terminals.removeLast())
        var relaidOut = busy
        relaidOut.worktrees[0].terminals[0].hasCustomName.toggle()
        try require(WorkInProgress.listsSameTerminals([busy], [relaidOut]) && !WorkInProgress.listsSameTerminals([busy], [renamedProject])
                        && !WorkInProgress.listsSameTerminals([busy], [movedTerminal]) && !WorkInProgress.listsSameTerminals([busy], [busy, renamedProject]),
                    "Work in progress is rebuilt only when terminals, their names or their locations change")
        split.sessions.agentStatuses = [:]
        split.sessions.runningAgents = [:]
        split.terminalSessionsDidChangeAgents()
        try require(split.workInProgress.isEmpty, "A finished agent leaves work in progress")
        print("PASS work in progress groups")

        let gitRoot = root.appendingPathComponent("grouped")
        try fm.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: gitRoot.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Initial"], at: gitRoot.path)
        let grouped = try split.addProject(gitRoot)
        let worktreesRoot = root.appendingPathComponent("worktrees")
        let review = try await GitService.createWorktree(project: grouped, branch: "review/one", root: worktreesRoot)
        let other = try await GitService.createWorktree(project: grouped, branch: "feature/two", root: worktreesRoot)
        try await split.flushPersistence()
        var stored = try WorkspaceDisk.load(from: splitFile)
        let projectIndex = stored.projects.firstIndex { $0.id == grouped.id }!
        stored.projects[projectIndex].worktrees += [review, other]
        try WorkspaceDisk.save(stored, to: splitFile)
        let groups = WorkspaceStore(fileURL: splitFile)
        let groupID = groups.addWorktreeGroup("  Revues ", projectID: grouped.id, moving: review.id)
        let groupedProject = { groups.projects.first { $0.id == grouped.id }! }
        try require(groupID != nil && groupedProject().worktreeGroups.map(\.name) == ["Revues"], "Create a named worktree group")
        try require(groupedProject().worktrees(in: groupID).map(\.id) == [review.id] && groupedProject().worktrees(in: nil).map(\.id) == [other.id],
                    "Grouped worktrees leave the ungrouped list")
        try require(!groups.moveWorktree(groupedProject().worktrees[0].id, to: groupID), "The main folder cannot join a group")
        try require(!groups.moveWorktree(other.id, to: UUID()), "Unknown groups are refused")
        groups.rename(groupID!, to: "Relectures")
        try require(groupedProject().worktreeGroups.map(\.name) == ["Relectures"], "Rename a worktree group")
        try await groups.flushPersistence()
        let persistedGroups = try WorkspaceDisk.load(from: splitFile)
        try require(persistedGroups == groups.state, "Groups persist")
        try require(SidebarFilterInput(folders: [], projects: groups.projects, query: "Relect").filtered().ungrouped.map(\.id) == [grouped.id],
                    "Filtering by group name reveals the project")
        groups.removeWorktreeGroup(groupID!)
        try require(groupedProject().worktreeGroups.isEmpty && groupedProject().worktrees(in: nil).count == 2, "Dissolving a group keeps its worktrees")
        print("PASS worktree groups")

        let adoptable = try await GitService.createWorktree(project: grouped, branch: "adopt/me", root: worktreesRoot)
        let lonelyRoot = root.appendingPathComponent("lonely")
        try fm.createDirectory(at: lonelyRoot, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: lonelyRoot.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Initial"], at: lonelyRoot.path)
        let lonely = try await GitService.createWorktree(project: Project(url: lonelyRoot), branch: "solo", root: worktreesRoot)
        let broken = worktreesRoot.appendingPathComponent("broken")
        try fm.createDirectory(at: broken, withIntermediateDirectories: true)
        try "gitdir: \(root.path)/missing/.git/worktrees/broken\n".write(to: broken.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: worktreesRoot.appendingPathComponent("notes"), withIntermediateDirectories: true)
        let clone = worktreesRoot.appendingPathComponent("clone")
        try fm.createDirectory(at: clone, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: clone.path)
        let extraRoot = root.appendingPathComponent("extra-worktrees")
        let extra = try await GitService.createWorktree(project: Project(url: lonelyRoot), branch: "extra", root: extraRoot)
        let scanned = [worktreesRoot, extraRoot]
        await groups.adoptWorktrees(in: scanned)
        try require(groupedProject().worktrees.contains { $0.path == adoptable.path && $0.name == "adopt/me" },
                    "A worktree of a known project is attached to it")
        try require(groupedProject().worktrees.filter { $0.path == review.path }.count == 1, "Known worktrees are not duplicated")
        let orphans = groups.orphanWorktrees
        try require(orphans.map(\.path).sorted() == [WorkspacePath.canonical(broken), lonely.path, extra.path].sorted(),
                    "Worktrees without a known project are orphans in every scanned folder, plain folders and clones are ignored")
        try require(orphans.first { $0.path == lonely.path }?.repositoryPath == WorkspacePath.canonical(lonelyRoot)
                        && orphans.first { $0.path == lonely.path }?.branch == "solo", "An orphan knows its main repository")
        try require(orphans.first { $0.folderName == "broken" }?.hasRepository == false, "An orphan whose repository is gone has none")
        groups.addRepository(of: orphans.first { $0.path == lonely.path }!)
        await groups.adoptWorktrees(in: scanned)
        try require(groups.orphanWorktrees.map(\.folderName) == ["broken"]
                        && groups.projects.contains { $0.worktrees.contains { $0.path == lonely.path } && $0.worktrees.contains { $0.path == extra.path } },
                    "Adding the main repository adopts its orphan")
        let lonelyRegistration = WorktreeFolder.registration(of: URL(fileURLWithPath: lonely.path))
        try require(lonelyRegistration?.deletingLastPathComponent().path == WorkspacePath.canonical(lonelyRoot.appendingPathComponent(".git/worktrees")),
                    "A linked worktree knows its own registration in the repository")
        try require(WorktreeFolder.registration(of: lonelyRoot) == nil && WorktreeFolder.registration(of: broken) == nil,
                    "A main folder or a broken worktree has no registration to remove")
        let linkedRoot = fm.temporaryDirectory.appendingPathComponent("agentui-store-link-\(UUID())")
        try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: URL(fileURLWithPath: WorkspacePath.canonical(root)))
        defer { try? fm.removeItem(at: linkedRoot) }
        let lonelyGitFile = URL(fileURLWithPath: lonely.path).appendingPathComponent(".git")
        let lonelyGitLink = try String(contentsOf: lonelyGitFile, encoding: .utf8)
        let canonicalRegistration = lonelyRegistration?.path ?? ""
        let linkedRegistration = linkedRoot.path + canonicalRegistration.dropFirst(WorkspacePath.canonical(root).count)
        try "gitdir: \(linkedRegistration)\n".write(to: lonelyGitFile, atomically: true, encoding: .utf8)
        let registrationThroughLink = WorktreeFolder.registration(of: URL(fileURLWithPath: lonely.path))
        try lonelyGitLink.write(to: lonelyGitFile, atomically: true, encoding: .utf8)
        try require(!canonicalRegistration.isEmpty && registrationThroughLink?.path == canonicalRegistration,
                    "A worktree whose Git link goes through a symlink still knows its registration")
        print("PASS worktree folder adoption")

        let reviewRemoval = Removal.worktree(projectID: grouped.id, worktreeID: review.id, name: review.name)
        let originHead = gitRoot.appendingPathComponent(".git/refs/remotes/gh/team/HEAD")
        _ = try await GitService.run(["remote", "add", "gh/team", "https://example.invalid/team.git"], at: gitRoot.path)
        try fm.createDirectory(at: originHead.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "ref: refs/remotes/gh/team/review/one\n".write(to: originHead, atomically: true, encoding: .utf8)
        groups.sessions.readBranches(of: groups.projects)
        let remoteDefault = await GitBranchProtection.report(at: review.path, in: gitRoot.path, checkedOutElsewhere: []).branch
        let remoteDefaultOffer = await groups.deletableBranch(for: reviewRemoval)
        try require(remoteDefault == .protected("review/one", .defaultBranch) && remoteDefaultOffer == nil,
                    "The removal dialog never offers to delete the branch a remote HEAD points to")
        try fm.removeItem(at: originHead.deletingLastPathComponent())
        _ = try await GitService.run(["remote", "remove", "gh/team"], at: gitRoot.path)
        let hidden = root.appendingPathComponent("hidden-review")
        _ = try await GitService.run(["worktree", "add", "-q", "-f", hidden.path, "review/one"], at: gitRoot.path)
        groups.sessions.readBranches(of: groups.projects)
        let hiddenCheckout = await GitBranchProtection.report(at: review.path, in: gitRoot.path, checkedOutElsewhere: []).branch
        let hiddenCheckoutOffer = await groups.deletableBranch(for: reviewRemoval)
        try require(hiddenCheckout == .protected("review/one", .checkedOutElsewhere) && hiddenCheckoutOffer == nil,
                    "The removal dialog never offers to delete a branch checked out in a worktree AgentUI doesn't know")
        _ = try await GitService.run(["worktree", "remove", "--force", hidden.path], at: gitRoot.path)
        groups.sessions.readBranches(of: groups.projects)
        let ownBranch = await GitBranchProtection.report(at: review.path, in: gitRoot.path, checkedOutElsewhere: []).branch
        try require(ownBranch == .deletable("review/one"), "A worktree's own branch isn't protected as checked out elsewhere")
        let reviewBranch = await groups.deletableBranch(for: reviewRemoval)
        try require(reviewBranch == "review/one", "The removal dialog offers to delete a worktree's branch")
        let mainBranch = await groups.deletableBranch(for: .worktree(projectID: grouped.id, worktreeID: groupedProject().worktrees[0].id, name: "Main"))
        try require(mainBranch == nil, "The main folder never offers to delete its branch")
        let reviewCleanup = try await groups.deleteWorktree(projectID: grouped.id, worktreeID: review.id, branch: .merged(confirmed: nil))
        let reviewLeft = try await GitService.run(["branch", "--list", "review/one"], at: gitRoot.path)
        try require(reviewCleanup == .deleted("review/one") && reviewLeft.isEmpty && !groupedProject().worktrees.contains { $0.id == review.id },
                    "Deleting a worktree with its merged branch removes both")
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Work"], at: other.path)
        do {
            try await groups.deleteWorktree(projectID: grouped.id, worktreeID: other.id, branch: .merged(confirmed: nil))
            throw WorkspaceError(message: "FAIL: unmerged worktree deleted")
        } catch let error as UnmergedBranchError {
            try require(error == UnmergedBranchError(branch: "feature/two", hasMainBranch: true) && fm.fileExists(atPath: other.path)
                            && groupedProject().worktrees.contains { $0.id == other.id },
                        "An unmerged branch is refused before removing anything, so the worktree stays")
        }
        let otherCleanup = try await groups.deleteWorktree(projectID: grouped.id, worktreeID: other.id)
        let otherLeft = try await GitService.run(["branch", "--list", "feature/two"], at: gitRoot.path)
        try require(otherCleanup == .notRequested && otherCleanup.notice == nil && otherCleanup.reportedDeletion == nil
                        && !otherLeft.isEmpty && !groupedProject().worktrees.contains { $0.id == other.id },
                    "Deleting the worktree only, after the refusal, keeps its unmerged branch")
        _ = try await GitService.run(["checkout", "-q", "-b", "adopt/switched"], at: adoptable.path)
        let switchedCleanup = try await groups.deleteWorktree(projectID: grouped.id, worktreeID: groupedProject().worktrees.first { $0.path == adoptable.path }!.id,
                                                              branch: .merged(confirmed: "adopt/me"))
        let adoptLeft = try await GitService.run(["branch", "--list", "adopt/me", "adopt/switched"], at: gitRoot.path)
        try require(switchedCleanup.branch == "adopt/me" && !switchedCleanup.isDeleted && switchedCleanup.failure?.contains("had left the branch") == true
                        && adoptLeft.contains("adopt/me") && adoptLeft.contains("adopt/switched") && !fm.fileExists(atPath: adoptable.path),
                    "A worktree that switched branches after the dialog is deleted, and neither the confirmed nor the new branch is")
        guard let lonelyProject = groups.projects.first(where: { $0.path == WorkspacePath.canonical(lonelyRoot) }),
              let onMain = lonelyProject.worktrees.first(where: { $0.path == extra.path }) else {
            throw WorkspaceError(message: "FAIL: the extra worktree belongs to the lonely project")
        }
        _ = try await GitService.run(["checkout", "-q", "-b", "feature"], at: lonelyRoot.path)
        _ = try await GitService.run(["checkout", "-q", "main"], at: extra.path)
        groups.sessions.readBranches(of: groups.projects)
        let onMainBranch = await groups.deletableBranch(for: .worktree(projectID: lonelyProject.id, worktreeID: onMain.id, name: onMain.name))
        try require(onMainBranch == nil, "The removal dialog never offers to delete main in a local-only repository")
        do {
            try await groups.deleteWorktree(projectID: lonelyProject.id, worktreeID: onMain.id, branch: .force)
            throw WorkspaceError(message: "FAIL: main deleted")
        } catch let error as WorkspaceError {
            try require(error.message.contains("main branch") && fm.fileExists(atPath: extra.path)
                            && groups.projects.contains { $0.worktrees.contains { $0.id == onMain.id } },
                        "Forcing the deletion of a worktree on main in a local-only repository is refused before removing anything")
        }
        let keptMain = try await groups.deleteWorktree(projectID: lonelyProject.id, worktreeID: onMain.id, branch: .merged(confirmed: "main"))
        let mainLeft = try await GitService.run(["branch", "--list", "main"], at: lonelyRoot.path)
        try require(keptMain.branch == "main" && !keptMain.isDeleted && keptMain.failure?.contains("main branch") == true
                        && !mainLeft.isEmpty && !fm.fileExists(atPath: extra.path)
                        && !groups.projects.contains { $0.worktrees.contains { $0.id == onMain.id } },
                    "From the sidebar, a worktree on the main branch is deleted and its branch kept with an explanation")
        print("PASS worktree deletion with or without its branch")

        let legacy = Data(#"{"version":1,"folders":[],"collapsed":[],"projects":[{"id":"\#(UUID())","name":"Old","path":"/tmp/old","worktrees":[{"id":"\#(UUID())","name":"Principal","path":"/tmp/old","isPrimary":true,"terminals":[]}]}]}"#.utf8)
        let decoded = try JSONDecoder().decode(Workspace.self, from: legacy)
        try require(decoded.projects[0].worktreeGroups.isEmpty && decoded.projects[0].worktrees[0].layouts.isEmpty && decoded.projects[0].worktrees[0].groupID == nil,
                    "Workspaces saved by older versions still load")
        try require(decoded.projects[0].worktrees[0].terminals.isEmpty, "Legacy fixture has no terminals")
        let legacyTerminals = try JSONDecoder().decode([TerminalRecord].self, from: Data(#"[{"id":"\#(UUID())","name":"Terminal"},{"id":"\#(UUID())","name":"Claude"},{"id":"\#(UUID())","name":"Mon serveur"}]"#.utf8))
        try require(legacyTerminals.map(\.hasCustomName) == [false, false, true], "Older default names become automatic, renamed terminals stay custom")
        print("PASS legacy workspace decoding")

        let titled = try split.addTerminal(projectID: splitProject.id, worktreeID: splitProject.worktrees[0].id)
        let renamed = try split.addTerminal(projectID: splitProject.id, worktreeID: splitProject.worktrees[0].id)
        split.rename(renamed.terminal.id, to: "Serveur")
        try require(titled.terminal.name == "Terminal" && !titled.terminal.hasCustomName, "New terminals are named Terminal until a conversation is found")
        split.applyConversationTitles([titled.terminal.id: "Corriger la connexion", renamed.terminal.id: "Autre"])
        try require(split.context(for: titled.terminal.id)?.terminal.name == "Corriger la connexion", "A terminal takes the name of its conversation")
        try require(split.context(for: renamed.terminal.id)?.terminal.name == "Serveur", "A renamed terminal keeps its name")
        split.useAutomaticName(renamed.terminal.id)
        split.applyConversationTitles([renamed.terminal.id: "Autre"])
        try require(split.context(for: renamed.terminal.id)?.terminal.name == "Autre", "A terminal can go back to the conversation name")
        print("PASS conversation names for terminals")

        let conversation = AgentConversation(agent: .claude, sessionID: "resume-twice", title: "Reprise", updatedAt: Date())
        let resumed = try split.resume(conversation, projectID: splitProject.id, worktreeID: splitProject.worktrees[0].id)
        do {
            try split.resume(conversation, projectID: splitProject.id, worktreeID: splitProject.worktrees[0].id)
            throw WorkspaceError(message: "FAIL: a conversation was resumed twice")
        } catch let error as WorkspaceError {
            try require(!error.message.hasPrefix("FAIL:"), error.message)
        }
        split.closeTerminal(resumed.terminal.id)
        try split.resume(conversation, projectID: splitProject.id, worktreeID: splitProject.worktrees[0].id)
        print("PASS a conversation is not resumed twice")

        let company = root.appendingPathComponent("Company")
        let mono = company.appendingPathComponent("Mono")
        let packages = mono.appendingPathComponent("packages")
        for repository in [company.appendingPathComponent("Site"), mono, packages.appendingPathComponent("Core"), packages.appendingPathComponent("UI")] {
            try fm.createDirectory(at: repository, withIntermediateDirectories: true)
            _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        }
        let nestedStore = WorkspaceStore(fileURL: root.appendingPathComponent("nested-import.json"))
        await nestedStore.importFolder(company, review: false)
        func importedFolder(_ name: String) -> ProjectFolder? { nestedStore.folders.first { $0.name == name } }
        func folderName(of project: String) -> String? {
            let folderID = nestedStore.projects.first { $0.name == project }?.folderID
            return nestedStore.folders.first { $0.id == folderID }?.name
        }
        try require(nestedStore.projects.count == 4, "Every nested repository is imported")
        try require(importedFolder("Mono")?.parentID == importedFolder("Company")?.id && importedFolder("packages")?.parentID == importedFolder("Mono")?.id,
                    "Virtual folders mirror the directory hierarchy")
        try require(folderName(of: "Site") == "Company" && folderName(of: "Mono") == "Mono" && folderName(of: "Core") == "packages" && folderName(of: "UI") == "packages",
                    "Each repository lands in the folder matching its location")
        let reimported = nestedStore.state
        await nestedStore.importFolder(company, review: false)
        try require(nestedStore.state == reimported, "Reimporting a nested hierarchy changes nothing")

        let flatStore = WorkspaceStore(fileURL: root.appendingPathComponent("flat.json"))
        await flatStore.importFolder(company)
        guard let plan = flatStore.pendingImport else { throw WorkspaceError(message: "FAIL: Several repositories open the import review") }
        let site = WorkspacePath.canonical(company.appendingPathComponent("Site"))
        let ui = WorkspacePath.canonical(packages.appendingPathComponent("UI"))
        await flatStore.importRepositories(plan, keeping: [site, ui], flattened: true)
        try require(flatStore.folders.map(\.name) == ["Company"] && Set(flatStore.projects.map(\.name)) == ["Site", "UI"]
                    && flatStore.projects.allSatisfy { $0.folderID == flatStore.folders[0].id },
                    "A flat import puts only the selected repositories in a single folder")
        try require(!flatStore.isImporting, "The import indicator is cleared once the import finishes")

        let work = nestedStore.addFolder("Work")
        guard let rootPlan = try await planned(company, in: nestedStore, into: work) else { throw WorkspaceError(message: "FAIL: reimport plan") }
        await nestedStore.importRepositories(rootPlan, keeping: Set(rootPlan.repositoryPaths), flattened: false)
        try require(importedFolder("Mono")?.parentID == work && importedFolder("Company") == nil,
                    "Reimporting into another folder moves the existing hierarchy there and drops the emptied folder")
        await nestedStore.importRepositories(rootPlan, keeping: Set(rootPlan.repositoryPaths), flattened: true)
        try require(nestedStore.folders.map(\.name) == ["Work"] && nestedStore.projects.allSatisfy { $0.folderID == work },
                    "A flat reimport removes the subfolders it emptied")
        print("PASS nested repository import with hierarchy, selection, flat mode and reimport")

        try require(legacyTerminals.allSatisfy { $0.resume == nil }, "Terminals saved by older versions have no agent session")
        let resume = AgentResume(agent: .claude, sessionID: "abc-123", skipsPermissions: true)
        try require(resume.command == ["claude", "--resume", "abc-123", "--dangerously-skip-permissions"], "Resume keeps the permission bypass")
        try require(AgentResume(agent: .codex, sessionID: "thread").command == ["codex", "resume", "thread"], "Codex resume command")
        try require(AgentResume(agent: .claude, sessionID: "--evil").command == nil, "Option-like session identifiers are never resumed")
        split.applyAgentResumes([titled.terminal.id: resume])
        try require(split.context(for: titled.terminal.id)?.terminal.resume == resume, "A running agent session is attached to its terminal")
        try await split.flushPersistence()
        let reloadedTerminals = try WorkspaceDisk.load(from: splitFile).projects.flatMap(\.worktrees).flatMap(\.terminals)
        try require(reloadedTerminals.first { $0.id == titled.terminal.id }?.resume == resume, "The agent session survives a relaunch")
        split.applyAgentResumes([titled.terminal.id: nil])
        try require(split.context(for: titled.terminal.id)?.terminal.resume == nil, "A finished agent session is forgotten")
        print("PASS agent sessions resume after relaunch")

        let relaunchFile = root.appendingPathComponent("relaunch.json")
        var relaunchProject = Project(url: root.appendingPathComponent("relaunch"))
        let agentTerminal = TerminalRecord(name: "Agent", resume: resume)
        let idleTerminal = relaunchProject.worktrees[0].terminals[0]
        relaunchProject.worktrees[0].terminals.append(agentTerminal)
        relaunchProject.worktrees[0].layouts = [TerminalLayout.terminal(idleTerminal.id).splitting(idleTerminal.id, with: agentTerminal.id, axis: .horizontal)]
        let relaunchState = Workspace(projects: [relaunchProject], selection: idleTerminal.id)
        try WorkspaceDisk.save(relaunchState, to: relaunchFile)
        let relaunched = WorkspaceStore(fileURL: relaunchFile)
        relaunched.restoreSessions()
        try require(relaunched.state == relaunchState && !relaunched.hasUnsavedChanges, "Relaunching keeps every terminal, name and split")
        print("PASS relaunch keeps the organization")

        let claudeArguments = ["node", "/usr/local/bin/claude", "--permission-mode", "bypassPermissions"]
        try require(ConversationAgent.claude.skipsPermissions(in: claudeArguments), "Claude permission mode bypass is detected")
        try require(ConversationAgent.codex.skipsPermissions(in: ["codex", "--yolo"]), "Codex yolo alias is detected")
        try require(!ConversationAgent.claude.skipsPermissions(in: ["claude", "--permission-mode", "plan"]), "Other permission modes are not a bypass")
        print("PASS permission bypass detection")
    }
}
