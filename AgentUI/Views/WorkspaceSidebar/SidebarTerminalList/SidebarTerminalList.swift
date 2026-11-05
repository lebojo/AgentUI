import SwiftUI
import UniformTypeIdentifiers

struct SidebarTerminalList: View {
    @Environment(WorkspaceStore.self) private var store

    let worktreeID: UUID
    let query: String

    var body: some View {
        let blocks = store.terminalBlocks(in: worktreeID, matching: query)
        ForEach(blocks) { block in
            SidebarTerminalBlockRow(block: block)
        }
        .onMove(perform: store.isReadOnly ? nil : { store.reorderTerminalBlocks(in: worktreeID, blocks, from: $0, to: $1) })
        .onInsert(of: store.acceptsTerminalInsert(in: worktreeID) ? [.agentUITerminal] : []) { index, providers in
            store.endDragging()
            Task {
                guard let dragged = await TerminalDragItem.terminalID(in: providers) else { return }
                store.insertTerminal(dragged, in: worktreeID, blocks, at: index)
            }
        }
    }
}
