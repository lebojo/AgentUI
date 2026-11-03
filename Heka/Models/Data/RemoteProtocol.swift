import CommonCrypto
import Foundation
import Network

enum RemoteProtocol {
    static var port: UInt16 {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HEKA_TEST_HOST_PORT"], let port = UInt16(value), port > 1024 {
            return port
        }
        #endif
        return 52741
    }
    static let version = 7
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
            let mappedIPv4 = b[..<10].allSatisfy { $0 == 0 } && b[10] == 0xff && b[11] == 0xff
            if mappedIPv4, (try? host(b[12...].map(String.init).joined(separator: "."))) != nil {
                return .ipv6(address)
            }
            if b[0] & 0xfe == 0xfc || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)
                || value == "::1" {
                return .ipv6(address)
            }
        }
        throw RemoteError(message: String(localized: "Enter the Mac’s local IP address, for example 192.168.1.42."))
    }
}

enum RemotePairing {
    static let identity = "Heka"
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
            throw RemoteError(message: String(localized: "Copy the pairing code shown on the Mac in Settings → Local Access."))
        }
        return value
    }

}

struct PairingKey: Equatable, Sendable {
    static let iterations: UInt32 = 100_000
    let data: Data

    init(code: String) throws {
        let password = try RemotePairing.normalized(code)
        let salt = Array("Heka pairing".utf8)
        var key = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), Self.iterations, &key, key.count)
        guard status == kCCSuccess else { throw RemoteError(message: String(localized: "Couldn’t set up connection encryption."), isPermanent: true) }
        data = Data(key)
    }

    static func derive(from code: String) async throws -> PairingKey {
        try await Task.detached(priority: .userInitiated) { try PairingKey(code: code) }.value
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
    case resizeTerminal(terminal: UUID, size: TerminalGridSize)
    case workspace(version: Int)
    case input(id: UUID, data: Data, message: String?)
    case newTerminal(project: UUID, worktree: UUID)
    case children(terminal: UUID, path: String)
    case text(terminal: UUID, path: String)
    case git(terminal: UUID)
    case github(terminal: UUID)
    case diff(terminal: UUID, change: GitChange, including: [GitDiffSection.Kind]?)
    case branches(terminal: UUID)
    case comparison(terminal: UUID, base: ComparisonBranch)
    case comparisonDiff(terminal: UUID, base: ComparisonBranch, change: GitChange)
    case conversations(terminal: UUID, fresh: Bool)
    case resume(terminal: UUID, conversation: AgentConversation)
    case launchAgent(terminal: UUID, agent: ConversationAgent)

    var waitsForInspectorSlot: Bool {
        switch self {
        case .newTerminal, .launchAgent, .resume, .input: false
        default: true
        }
    }

    var timeout: Duration {
        switch self {
        case .git, .github, .diff, .branches, .comparison, .comparisonDiff, .conversations, .resume: .seconds(60)
        default: .seconds(15)
        }
    }
}

struct RemoteReply: Codable, Sendable {
    var payload: Data?
    var error: String?

    static func success(_ value: some Encodable) throws -> Self {
        let payload = try JSONEncoder().encode(value)
        guard payload.count <= RemoteProtocol.maximumPayload else { throw RemoteError(message: String(localized: "Response too large.")) }
        return Self(payload: payload)
    }

    static func fitting<Element>(_ elements: [Element], _ value: ([Element], Int) -> some Encodable) throws -> Self {
        var count = elements.count
        while true {
            let payload = try JSONEncoder().encode(value(Array(elements.prefix(count)), elements.count - count))
            if payload.count <= RemoteProtocol.maximumPayload { return Self(payload: payload) }
            guard count > 0 else { throw RemoteError(message: String(localized: "Response too large.")) }
            count = min(count - 1, count * RemoteProtocol.maximumPayload / payload.count * 9 / 10)
        }
    }

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        if let error { throw RemoteError(message: error) }
        guard let payload else { throw RemoteError(message: String(localized: "Empty response from the Mac.")) }
        return try JSONDecoder().decode(type, from: payload)
    }
}

enum RemoteEvent: Codable, Sendable {
    case workspace(Workspace)
    case terminal(RemoteTerminalSnapshot)
    case terminalClosed
    case failure(String)
    case inputResult(request: UUID, error: String?)
    case repositoryChanged
    case conversationsChanged
    case installedAgents([ConversationAgent])
    case terminalAgents([UUID: ConversationAgent])
}

struct RemoteRejection: Encodable, Sendable {
    private enum CodingKeys: String, CodingKey { case error }

    let message: String

    init(_ message: String) {
        self.message = message
    }

    func encode(to encoder: any Encoder) throws {
        try RemoteEvent.failure(message).encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .error)
    }
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
