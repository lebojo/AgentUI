import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let hekaTerminal = UTType(exportedAs: "ch.jordanchap.heka.terminal", conformingTo: .data)
}

struct TerminalDragItem: Codable, Transferable, Sendable {
    let terminalID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .hekaTerminal)
    }

    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.register(self)
        return provider
    }

    static func terminalID(in providers: [NSItemProvider]) async -> UUID? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.hekaTerminal.identifier) }) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: TerminalDragItem.self) { continuation.resume(returning: try? $0.get().terminalID) }
        }
    }
}
