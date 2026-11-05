import SwiftUI

struct SidebarTerminalBlockRow: View {
    @Environment(WorkspaceStore.self) private var store

    let block: SidebarTerminalBlock

    private var tag: UUID { block.isSplit ? block.selectionTag(for: store.selection) : block.id }

    var body: some View {
        SidebarSubagentDisclosure(expansionID: block.id, terminalIDs: block.terminalIDs) {
            HStack(spacing: 0) {
                if let terminal = block.singleTerminal {
                    SidebarSingleTerminalLabel(terminal: terminal)
                } else {
                    SidebarSplitBlockLabel(block: block)
                }
            }
            .tag(tag)
            .contextMenu {
                if let terminal = block.singleTerminal { SidebarTerminalMenu(terminal: terminal) }
            }
            .swipeActions(edge: .trailing) {
                if let terminal = block.singleTerminal { RemovalButton(removal: .terminal(terminal.id), placement: .swipe) }
            }
        }
    }
}
