import SwiftUI
import UniformTypeIdentifiers

struct TerminalDropZone: ViewModifier {
    @Environment(WorkspaceStore.self) private var store

    @State private var edge: DropEdge?
    @State private var size: CGSize = .zero

    let terminalID: UUID

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .overlay(alignment: edge?.alignment ?? .center) {
                if let edge { TerminalDropHighlight(edge: edge, size: size) }
            }
            .onDrop(of: [.agentUITerminal], delegate: TerminalDropDelegate(edge: $edge, store: store, terminalID: terminalID, size: size))
    }
}
