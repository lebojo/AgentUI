import SwiftUI

struct SidebarWorktreeRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store

    @State private var isInserted = false

    let projectID: UUID
    let worktreeGroups: [WorktreeGroup]
    let worktree: Worktree
    let query: String
    let showAll: Bool

    private var terminalQuery: String {
        showAll || matches(worktree.displayName) ? "" : query
    }
    private var isExpanded: Binding<Bool> {
        guard isInserted else { return .constant(false) }
        return query.isEmpty ? Bindable(store)[expanded: worktree.id] : .constant(true)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            SidebarTerminalList(worktreeID: worktree.id, query: terminalQuery)
            if worktree.terminals.isEmpty {
                Button("Open Terminal") { store.openTerminal(projectID: projectID, worktreeID: worktree.id, launch: settings.agentLaunch) }
                    .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            SidebarWorktreeLabel(projectID: projectID, worktreeGroups: worktreeGroups, worktreeID: worktree.id, name: worktree.name,
                                 displayName: worktree.displayName, path: worktree.path, groupID: worktree.groupID)
        }
        .task { isInserted = true }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
}
