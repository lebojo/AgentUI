import SwiftUI

struct SidebarWorktreeRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store

    @State private var isInserted = false

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let project: Project
    let worktree: Worktree
    let query: String
    let showAll: Bool

    private var terminals: [TerminalRecord] {
        worktree.terminals.filter { showAll || matches(worktree.displayName) || matches($0.name) }
    }
    private var isExpanded: Binding<Bool> {
        guard isInserted else { return .constant(false) }
        return query.isEmpty ? Bindable(store)[expanded: worktree.id] : .constant(true)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            SidebarTerminalList(sheet: $sheet, removal: $removal, worktree: worktree, terminals: terminals)
            if worktree.terminals.isEmpty {
                Button("Open Terminal") { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
                    .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            SidebarWorktreeLabel(sheet: $sheet, removal: $removal, project: project, worktree: worktree)
        }
        .task { isInserted = true }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
}
