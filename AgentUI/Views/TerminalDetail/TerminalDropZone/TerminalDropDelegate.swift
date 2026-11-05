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
        edge = nil
        store.endDragging()
        let providers = info.itemProviders(for: [.agentUITerminal])
        let edge = DropEdge(location: info.location, in: size)
        Task {
            guard let dragged = await TerminalDragItem.terminalID(in: providers) else { return }
            store.moveTerminal(dragged, beside: terminalID, edge: edge)
        }
        return !providers.isEmpty
    }
}
