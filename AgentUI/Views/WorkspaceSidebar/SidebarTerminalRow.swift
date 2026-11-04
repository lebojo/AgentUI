import SwiftUI
import AppKit

struct SidebarTerminalRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let terminal: TerminalRecord
    let worktree: Worktree

    private var session: TerminalSession? { store.sessions.session(terminal.id) }
    private var subagents: [Subagent] {
        (session?.subagents ?? []).filter { $0.isVisible || $0.id == store.selection }
    }

    private var row: some View {
        SidebarTerminalLabel(name: terminal.name, session: session,
                             divergentBranch: store.sessions.divergentBranch(for: terminal.id, worktreePath: worktree.path))
        .padding(.vertical, Spacing.xxs)
        .tag(terminal.id)
        .contextMenu { SidebarTerminalMenu(sheet: $sheet, removal: $removal, terminal: terminal) }
        .swipeActions(edge: .trailing) {
            RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .swipe)
        }
    }

    var body: some View {
        if subagents.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: $store[expanded: terminal.id]) {
                ForEach(subagents) { subagent in
                    SidebarSubagentRow(subagent: subagent)
                }
            } label: {
                row
            }
        }
    }
}
