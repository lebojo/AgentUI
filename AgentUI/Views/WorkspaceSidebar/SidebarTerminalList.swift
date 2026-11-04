import SwiftUI

struct SidebarTerminalList: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let worktree: Worktree
    let terminals: [TerminalRecord]

    private var blocks: [SidebarTerminalBlock] { worktree.terminalBlocks(showing: terminals) }

    var body: some View {
        ForEach(blocks) { block in
            if block.isSplit {
                SidebarSplitBlockRow(sheet: $sheet, removal: $removal, store: store, block: block, worktreePath: worktree.path)
            } else {
                SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: block.terminals[0], worktree: worktree)
            }
        }
        .onMove(perform: store.isReadOnly ? nil : { store.reorderTerminalBlocks(in: worktree.id, blocks, from: $0, to: $1) })
    }
}
