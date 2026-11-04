import SwiftUI

struct SidebarSplitBlockRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let block: SidebarTerminalBlock
    let worktreePath: String

    private var focusedID: UUID? { block.terminals.first { $0.id == store.selection }?.id }
    private var symbolName: String { block.axis == .vertical ? "rectangle.split.1x2" : "rectangle.split.2x1" }
    private var subagents: [Subagent] {
        block.terminals.flatMap { store.sessions.session($0.id)?.subagents ?? [] }
            .filter { $0.isVisible || $0.id == store.selection }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbolName)
                .font(Typography.s).foregroundStyle(Palette.textSecondary)
                .padding(.top, Spacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(block.terminals) { terminal in
                    SidebarSplitMemberRow(sheet: $sheet, removal: $removal, terminal: terminal,
                                          worktreePath: worktreePath, isFocused: terminal.id == focusedID)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .tag(focusedID ?? block.id)
        .help("Terminals shown side by side in a split view")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split view")
    }

    var body: some View {
        if subagents.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: $store[expanded: block.id]) {
                ForEach(subagents) { subagent in
                    SidebarSubagentRow(subagent: subagent)
                }
            } label: {
                row
            }
        }
    }
}
