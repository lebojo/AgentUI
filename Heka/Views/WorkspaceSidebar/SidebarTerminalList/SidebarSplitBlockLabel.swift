import SwiftUI

struct SidebarSplitBlockLabel: View {
    @Environment(WorkspaceStore.self) private var store

    let block: SidebarTerminalBlock

    private var focusedID: UUID? { block.selectedMember(store.selection) }
    private var symbolName: String { block.axis == .vertical ? "rectangle.split.1x2" : "rectangle.split.2x1" }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbolName)
                .font(Typography.s).foregroundStyle(Palette.textSecondary)
                .padding(.top, Spacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(block.terminals) { terminal in
                    SidebarSplitMemberRow(terminal: terminal, isFocused: terminal.id == focusedID)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .help("Terminals shown side by side in a split view")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split view")
    }
}
