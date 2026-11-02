import Foundation

enum LoginShell {
    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let configured = environment["SHELL"] ?? "/bin/zsh"
        return FileManager.default.isExecutableFile(atPath: configured) ? configured : "/bin/zsh"
    }

    static func variable(_ name: String) async -> String? {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
        let marker = "AGENTUI-\(UUID().uuidString)"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let data = try? await CommandRunner.run(URL(fileURLWithPath: path()), ["-l", "-i", "-c", "printf '%s' \"$1\"; printenv \"$2\"", "agentui", marker, name],
                                                      at: home, timeout: 10, limit: 65_536, readOnly: true) else { return nil }
        let output = String(decoding: data, as: UTF8.self)
        guard let range = output.range(of: marker, options: .backwards) else { return nil }
        let value = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
