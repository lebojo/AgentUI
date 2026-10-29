import Foundation
import Darwin

enum BridgeMailbox {
    enum Envelope: Sendable {
        case request, response

        var limit: Int {
            switch self {
            case .request: 1_048_576
            case .response: 67_108_864
            }
        }

        var invalidMessage: String {
            switch self {
            case .request: "Requête invalide."
            case .response: "Réponse d’AgentUI invalide."
            }
        }

        var oversizedMessage: String {
            switch self {
            case .request: "Requête trop volumineuse."
            case .response: "Réponse d’AgentUI trop volumineuse."
            }
        }
    }

    @concurrent static func request(at file: URL) async throws -> BridgeRequest {
        try JSONDecoder().decode(BridgeRequest.self, from: try contents(of: file, as: .request))
    }

    @concurrent static func write(_ response: BridgeResponse, to file: URL) async throws {
        try JSONEncoder().encode(response).write(to: file, options: .atomic)
    }

    static func contents(of file: URL, as envelope: Envelope) throws -> Data {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw WorkspaceError(message: envelope.invalidMessage) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw WorkspaceError(message: envelope.invalidMessage)
        }
        guard info.st_size <= envelope.limit else { throw WorkspaceError(message: envelope.oversizedMessage) }
        let data = try handle.read(upToCount: envelope.limit + 1) ?? Data()
        guard data.count <= envelope.limit else { throw WorkspaceError(message: envelope.oversizedMessage) }
        return data
    }
}
