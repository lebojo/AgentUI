import Foundation

struct SavedHost: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var addresses: [String]
    let pairingAccount: String

    init(id: UUID = UUID(), name: String, addresses: [String], pairingAccount: String? = nil) {
        self.id = id
        self.name = name
        self.addresses = addresses
        self.pairingAccount = pairingAccount ?? "remotePairingCode.\(id.uuidString)"
    }

    var summary: String { addresses.joined(separator: ", ") }

    func preferring(_ address: String) -> SavedHost {
        var host = self
        host.addresses = [address] + addresses.filter { $0 != address }
        return host
    }
}
