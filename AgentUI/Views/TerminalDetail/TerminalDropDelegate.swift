import SwiftUI
import UniformTypeIdentifiers

struct TerminalDropDelegate: DropDelegate {
    @Binding var edge: DropEdge?

    let store: WorkspaceStore
    let terminalID: UUID
    let size: CGSize

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.agentUITerminal]), let dragged = store.draggedTerminal else { return false }
        return store.canMoveTerminal(dragged, beside: terminalID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let current = DropEdge(location: info.location, in: size)
        if edge != current { edge = current }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = DropEdge(location: info.location, in: size)
        edge = nil
        guard let provider = info.itemProviders(for: [.agentUITerminal]).first else { return false }
        _ = provider.loadTransferable(type: TerminalDragItem.self) { [store, terminalID] result in
            guard let item = try? result.get() else { return }
            Task { @MainActor in store.moveTerminal(item.terminalID, beside: terminalID, edge: target) }
        }
        return true
    }
}
