import SwiftUI
import UniformTypeIdentifiers

struct SidebarTerminalList: View {
    @Environment(WorkspaceStore.self) private var store

    let worktree: Worktree
    let terminals: [TerminalRecord]

    var body: some View {
        let blocks = worktree.terminalBlocks(showing: terminals)
        ForEach(blocks) { block in
            if block.isSplit {
                SidebarSplitBlockRow(block: block)
            } else {
                SidebarTerminalRow(terminal: block.terminals[0])
            }
        }
        .onMove(perform: store.isReadOnly ? nil : { store.reorderTerminalBlocks(in: worktree.id, blocks, from: $0, to: $1) })
        .onInsert(of: store.isReadOnly ? [] : [.agentUITerminal]) { index, _ in
            store.insertDraggedTerminal(in: worktree.id, blocks, at: index)
        }
    }
}
