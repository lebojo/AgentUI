import Foundation

struct SidebarFilterResult {
    struct Group: Identifiable {
        let folder: ProjectFolder
        let projects: [Project]
        let total: Int
        var id: UUID { folder.id }
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
            matches(project.name) || project.worktrees.contains { matches($0.name) || $0.terminals.contains { matches($0.name) } }
        }
        let byFolder = Dictionary(grouping: projects, by: \.folderID)
        let groups = folders.compactMap { folder -> SidebarFilterResult.Group? in
            let all = byFolder[folder.id] ?? []
            let visible = matches(folder.name) ? all : all.filter(projectMatches)
            guard matches(folder.name) || !visible.isEmpty else { return nil }
            return .init(folder: folder, projects: visible, total: all.count)
        }
        return SidebarFilterResult(groups: groups, ungrouped: (byFolder[nil] ?? []).filter(projectMatches))
    }
}
