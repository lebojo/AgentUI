import Foundation
import Darwin

struct ReadCommandError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ReadCommand {
    static func executable(_ name: String) -> URL? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", NSHomeDirectory() + "/.local/bin"]
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(_ executable: URL, _ arguments: [String], at path: String,
                    timeout: TimeInterval = 20, limit: Int = 2_097_152, gitConfiguration: [String: String] = [:]) async throws -> Data {
        try await CommandRunner.run(executable, arguments, at: path, timeout: timeout, limit: limit, readOnly: true,
                                    gitConfiguration: gitConfiguration)
    }
}
