import Foundation
import Darwin

enum BridgeMailbox {
    static let requestLimit = 1_048_576

    @concurrent static func request(at file: URL) async throws -> BridgeRequest {
        try JSONDecoder().decode(BridgeRequest.self, from: try boundedContents(of: file, limit: requestLimit))
    }

    @concurrent static func write(_ response: BridgeResponse, to file: URL) async throws {
        try JSONEncoder().encode(response).write(to: file, options: .atomic)
    }

    static func boundedContents(of file: URL, limit: Int) throws -> Data {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw WorkspaceError(message: "Requête invalide.")
        }
        guard info.st_size <= limit else { throw WorkspaceError(message: "Requête trop volumineuse.") }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw WorkspaceError(message: "Requête trop volumineuse.") }
        return data
    }
}
