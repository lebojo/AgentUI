import CommonCrypto
import Foundation
import Network

enum RemoteProtocol {
    static var port: UInt16 {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["AGENTUI_TEST_HOST_PORT"], let port = UInt16(value), port > 1024 {
            return port
        }
        #endif
        return 52741
    }
    static let version = 5
    static let maximumFrame = 4 * 1024 * 1024
    static let maximumPayload = maximumFrame / 4 * 3 - 4096

    static func host(_ value: String) throws -> NWEndpoint.Host {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = IPv4Address(value) {
            let b = Array(address.rawValue)
            if b[0] == 10 || b[0] == 127 || (b[0] == 192 && b[1] == 168)
                || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 169 && b[1] == 254) {
                return .ipv4(address)
            }
        }
        if let address = IPv6Address(value) {
            let b = Array(address.rawValue)
            if b[0] & 0xfe == 0xfc || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)
                || value == "::1" {
                return .ipv6(address)
            }
        }
        throw RemoteError(message: "Entre l’adresse IP locale du Mac, par exemple 192.168.1.42.")
    }
}

enum RemotePairing {
    static let identity = "AgentUI"
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let length = 12

    static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<length).map { _ in alphabet.randomElement(using: &generator)! }
        return stride(from: 0, to: length, by: 4).map { String(characters[$0..<($0 + 4)]) }.joined(separator: "-")
    }

    static func normalized(_ code: String) throws -> String {
        let value = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard value.count == length, value.allSatisfy(alphabet.contains) else {
            throw RemoteError(message: "Recopie le code d’appairage affiché sur le Mac dans Réglages → Accès local.")
        }
        return value
    }

}

struct PairingKey: Equatable, Sendable {
    static let iterations: UInt32 = 100_000
    let data: Data

    init(code: String) throws {
        let password = try RemotePairing.normalized(code)
        let salt = Array("AgentUI pairing".utf8)
        var key = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), Self.iterations, &key, key.count)
        guard status == kCCSuccess else { throw RemoteError(message: "Impossible de préparer le chiffrement de la connexion.", isPermanent: true) }
        data = Data(key)
    }
}

struct RemoteError: LocalizedError, Sendable {
    let message: String
    var isPermanent = false
    var errorDescription: String? { message }
}

enum RemoteRequest: Codable, Sendable {
    case watch(version: Int, terminal: UUID?, prefersChat: Bool)
    case streamInput(request: UUID, terminal: UUID, data: Data, message: String?)
    case workspace(version: Int)
    case terminal(id: UUID, offset: Int)
    case input(id: UUID, data: Data, message: String?)
    case newTerminal(project: UUID, worktree: UUID)
    case children(terminal: UUID, path: String)
    case text(terminal: UUID, path: String)
    case git(terminal: UUID)
    case github(terminal: UUID)
    case diff(terminal: UUID, change: GitChange)
    case conversations(terminal: UUID)
    case resume(terminal: UUID, conversation: AgentConversation)
    case launchAgent(terminal: UUID, agent: ConversationAgent)
}

struct RemoteReply: Codable, Sendable {
    var payload: Data?
    var error: String?

    static func success(_ value: some Encodable) throws -> Self {
        let payload = try JSONEncoder().encode(value)
        guard payload.count <= RemoteProtocol.maximumPayload else { throw RemoteError(message: "Réponse trop volumineuse.") }
        return Self(payload: payload)
    }

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        if let error { throw RemoteError(message: error) }
        guard let payload else { throw RemoteError(message: "Réponse vide du Mac.") }
        return try JSONDecoder().decode(type, from: payload)
    }
}


enum RemoteEvent: Codable, Sendable {
    case workspace(Workspace)
    case terminal(RemoteTerminalSnapshot)
    case failure(String)
    case inputResult(request: UUID, error: String?)
    case repositoryChanged
    case conversationsChanged
    case installedAgents([ConversationAgent])
}

struct RemoteDiff: Codable, Sendable {
    struct Section: Codable, Sendable {
        let kind: GitDiffSection.Kind
        let patch: String
        let isComplete: Bool
    }
    let path: String
    let sections: [Section]

    init(_ diff: GitDiff) {
        path = diff.path
        sections = diff.sections.map {
            Section(kind: $0.kind, patch: $0.patch, isComplete: $0.isComplete)
        }
    }

    var diff: GitDiff {
        GitDiff(path: path, sections: sections.map {
            GitDiffSection(kind: $0.kind, patch: $0.patch, isComplete: $0.isComplete)
        })
    }
}
