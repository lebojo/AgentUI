import SwiftUI
import UniformTypeIdentifiers

struct TerminalDropZone: ViewModifier {
    @Environment(WorkspaceStore.self) private var store

    @State private var edge: DropEdge?
    @State private var geometry = PaneGeometry()

    let terminalID: UUID

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { geometry.size = $0 }
            .overlay(alignment: edge?.alignment ?? .center) {
                if let edge { TerminalDropHighlight(edge: edge, size: geometry.size) }
            }
            .onDrop(of: [.hekaTerminal], delegate: TerminalDropDelegate(edge: $edge, store: store, terminalID: terminalID, geometry: geometry))
    }
}
