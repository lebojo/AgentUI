import SwiftUI

struct SidebarProjectRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let project: Project
    let query: String
    let showAll: Bool

    private var showsEverything: Bool { showAll || matches(project.name) }
    private var visibleGroups: [WorktreeGroup] {
        project.worktreeGroups.filter { showsEverything || matches($0.name) || !visibleWorktrees(in: $0.id).isEmpty }
    }
    private var isExpanded: Binding<Bool> {
        query.isEmpty ? Bindable(store)[expanded: project.id] : .constant(true)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(project.worktrees.filter(\.isPrimary)) { worktree in
                SidebarTerminalList(sheet: $sheet, removal: $removal, worktree: worktree,
                                    terminals: worktree.terminals.filter { showsEverything || matches($0.name) })
                if worktree.terminals.isEmpty {
                    Button("Open Terminal") { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
                        .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            ForEach(visibleGroups) { group in
                SidebarWorktreeGroupRow(sheet: $sheet, removal: $removal, project: project, group: group, query: query,
                                        showAll: showsEverything || matches(group.name))
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderWorktreeGroups(in: project.id, visibleGroups.map(\.id), from: $0, to: $1) })
            let ungrouped = visibleWorktrees(in: nil)
            ForEach(ungrouped) { worktree in
                SidebarWorktreeRow(sheet: $sheet, removal: $removal, project: project, worktree: worktree, query: query,
                                   showAll: showsEverything)
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderWorktrees(in: project.id, ungrouped.map(\.id), from: $0, to: $1) })
        } label: {
            SidebarProjectLabel(sheet: $sheet, removal: $removal, project: project)
        }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
    private func visibleWorktrees(in groupID: UUID?) -> [Worktree] {
        project.worktrees(in: groupID).filter { worktree in
            showsEverything || matches(worktree.displayName) || worktree.terminals.contains { matches($0.name) }
        }
    }
}
