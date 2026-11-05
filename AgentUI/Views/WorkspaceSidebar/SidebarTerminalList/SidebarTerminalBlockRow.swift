import SwiftUI

struct SidebarTerminalBlockRow: View {
    let block: SidebarTerminalBlock

    var body: some View {
        SidebarSubagentDisclosure(expansionID: block.id, terminalIDs: block.terminalIDs) {
            if block.isSplit {
                SidebarSplitBlockLabel(block: block)
            } else {
                SidebarSingleTerminalLabel(terminal: block.terminals[0])
            }
        }
    }
}
