import SwiftUI

struct TerminalDragSource: ViewModifier {
    @Environment(WorkspaceStore.self) private var store

    let terminalID: UUID

    func body(content: Content) -> some View {
        content.onDrag {
            store.beginDragging(terminalID)
            return TerminalDragItem(terminalID: terminalID).itemProvider
        }
    }
}
