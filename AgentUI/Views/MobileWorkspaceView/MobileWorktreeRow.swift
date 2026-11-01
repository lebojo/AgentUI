import SwiftUI

struct MobileWorktreeRow: View {
    @Environment(MobileWorkspaceStore.self) private var store

    @State private var expanded = true

    let worktree: Worktree

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(worktree.terminals) { terminal in
                NavigationLink(value: MobileSidebar.Selection.terminal(terminal.id)) {
                    Label { Text(terminal.name) } icon: { TerminalIcon(agent: store.terminalAgents[terminal.id]) }
                }
                    .selectionDisabled(false)
            }
        } label: {
            Label(worktree.name, systemImage: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
        }
        .selectionDisabled()
    }
}
