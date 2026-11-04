import SwiftUI

struct TerminalDragSource: ViewModifier {
    @Environment(WorkspaceStore.self) private var store

    let terminalID: UUID

    func body(content: Content) -> some View {
        content.onDrag {
            guard !store.isReadOnly else { return NSItemProvider() }
            store.beginDragging(terminalID)
            return TerminalDragItem(terminalID: terminalID).itemProvider
        }
    }
}
