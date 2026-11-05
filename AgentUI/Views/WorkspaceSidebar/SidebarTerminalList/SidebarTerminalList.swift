import SwiftUI
import UniformTypeIdentifiers

struct SidebarTerminalList: View {
    @Environment(WorkspaceStore.self) private var store

    let worktree: Worktree
    let terminals: [TerminalRecord]

    var body: some View {
        let blocks = worktree.terminalBlocks(showing: terminals)
        ForEach(blocks) { block in
            SidebarTerminalBlockRow(block: block)
        }
        .onMove(perform: store.isReadOnly ? nil : { store.reorderTerminalBlocks(in: worktree.id, blocks, from: $0, to: $1) })
        .onInsert(of: store.isReadOnly ? [] : [.agentUITerminal]) { index, providers in
            store.endDragging()
            Task {
                guard let dragged = await TerminalDragItem.terminalID(in: providers) else { return }
                store.insertTerminal(dragged, in: worktree.id, blocks, at: index)
            }
        }
    }
}
