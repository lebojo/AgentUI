import Foundation
import Observation

// This test executable compiles the production store with inert terminal processes.
// Real SwiftTerm and PTY behavior is covered by integration.py against the actual app.
@MainActor final class TerminalSessions {
    func close(_ id: UUID) {}
    func start(_ context: TerminalContext, command: [String] = []) {}
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func mark() { lock.lock(); changed = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return changed }
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
        print("PASS granular observation, coalescing and explicit durable flush")

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
    }
}
