import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let agentUITerminal = UTType(exportedAs: "ch.jordanchap.agentui.terminal", conformingTo: .data)
}

struct TerminalDragItem: Codable, Transferable, Sendable {
    let terminalID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentUITerminal)
    }

    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.register(self)
        return provider
    }
}
