import Foundation

enum LoginShell {
    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let configured = environment["SHELL"] ?? "/bin/zsh"
        return FileManager.default.isExecutableFile(atPath: configured) ? configured : "/bin/zsh"
    }
}
