import Foundation

struct PairingInvitation: Equatable, Sendable {
    private enum Field: String {
        case id, name, hosts, code
    }

    private static let scheme = "agentui"
    private static let action = "pair"
    private static let separator: Character = ","

    let hostID: UUID
    let name: String
    let addresses: [String]
    let code: String

    init(hostID: UUID, name: String, addresses: [String], code: String) {
        self.hostID = hostID
        self.name = name
        self.addresses = addresses
        self.code = code
    }

    init(scanned text: String) throws {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == Self.scheme, components.host == Self.action else { throw Self.unrecognized }
        let items = components.queryItems ?? []
        let value = { (field: Field) in items.first { $0.name == field.rawValue }?.value }
        let addresses = (value(.hosts) ?? "").split(separator: Self.separator).map(String.init)
            .filter { (try? RemoteProtocol.host($0)) != nil }
        guard let hostID = value(.id).flatMap(UUID.init(uuidString:)), let code = value(.code),
              (try? RemotePairing.normalized(code)) != nil, let first = addresses.first else { throw Self.unrecognized }
        self.hostID = hostID
        self.name = value(.name).flatMap { $0.isEmpty ? nil : $0 } ?? first
        self.addresses = addresses
        self.code = code
    }

    var link: String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.action
        components.queryItems = [
            URLQueryItem(name: Field.id.rawValue, value: hostID.uuidString),
            URLQueryItem(name: Field.name.rawValue, value: name),
            URLQueryItem(name: Field.hosts.rawValue, value: addresses.joined(separator: String(Self.separator))),
            URLQueryItem(name: Field.code.rawValue, value: code),
        ]
        return components.string ?? ""
    }

    private static var unrecognized: RemoteError {
        RemoteError(message: String(localized: "This QR code doesn’t come from AgentUI. Scan the code shown on the Mac in Settings → Local Access."))
    }
}
