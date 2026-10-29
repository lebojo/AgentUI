import Foundation

struct SidebarFilterResult {
    struct Group: Identifiable {
        let folder: ProjectFolder
        let subgroups: [Group]
        let projects: [Project]
        let total: Int
        let showsAll: Bool
        var id: UUID { folder.id }
        var isEmpty: Bool { subgroups.isEmpty && projects.isEmpty }
    }
    var groups: [Group] = []
    var ungrouped: [Project] = []
}

struct SidebarFilterInput: Equatable {
    let folders: [ProjectFolder]
    let projects: [Project]
    let query: String

    func filtered() -> SidebarFilterResult {
        func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
        func projectMatches(_ project: Project) -> Bool {
            matches(project.name) || project.worktreeGroups.contains { matches($0.name) }
                || project.worktrees.contains { matches($0.name) || $0.terminals.contains { matches($0.name) } }
        }
        let byFolder = Dictionary(grouping: projects, by: \.folderID)
        func total(_ folder: ProjectFolder) -> Int {
            (byFolder[folder.id]?.count ?? 0) + folders.children(of: folder.id).map(total).reduce(0, +)
        }
        func group(_ folder: ProjectFolder, revealed ancestorRevealed: Bool) -> SidebarFilterResult.Group? {
            let revealed = ancestorRevealed || matches(folder.name)
            let all = byFolder[folder.id] ?? []
            let visible = revealed ? all : all.filter(projectMatches)
            let subgroups = folders.children(of: folder.id).compactMap { group($0, revealed: revealed) }
            guard revealed || !visible.isEmpty || !subgroups.isEmpty else { return nil }
            return .init(folder: folder, subgroups: subgroups, projects: visible, total: total(folder), showsAll: revealed)
        }
        let groups = folders.children(of: nil).compactMap { group($0, revealed: false) }
        return SidebarFilterResult(groups: groups, ungrouped: (byFolder[nil] ?? []).filter(projectMatches))
    }
}
