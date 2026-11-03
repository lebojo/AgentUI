import SwiftUI

extension View {
    func terminalDragSource(_ terminalID: UUID) -> some View {
        modifier(TerminalDragSource(terminalID: terminalID))
    }

    func terminalDropZone(_ terminalID: UUID) -> some View {
        modifier(TerminalDropZone(terminalID: terminalID))
    }
}
