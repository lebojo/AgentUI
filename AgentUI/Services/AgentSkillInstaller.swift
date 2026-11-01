import Foundation

struct AgentSkillInstaller: Sendable {
    static let name = "agentui"
    private static let fileName = "SKILL.md"

    let content: String
    let home: URL

    static var bundled: AgentSkillInstaller? {
        guard let url = Bundle.main.url(forResource: "SKILL", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return AgentSkillInstaller(content: content, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var sharedDirectory: URL { home.appending(path: ".agents/skills/\(Self.name)") }
    var claudeDirectory: URL { home.appending(path: ".claude/skills/\(Self.name)") }
    var version: Int { Self.version(of: content) }

    var status: AgentSkillStatus {
        let copies = [sharedDirectory, claudeDirectory].map(installedContent)
        if copies.allSatisfy({ $0.map(isCurrent) ?? false }) { return .installed }
        return copies.contains { $0 != nil } ? .outdated : .notInstalled
    }

    func install() throws {
        let shared = installedContent(in: sharedDirectory)
        if !(shared.map(isCurrent) ?? false) {
            try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: sharedDirectory.appending(path: Self.fileName), options: .atomic)
        }
        guard installedContent(in: claudeDirectory) != installedContent(in: sharedDirectory) else { return }
        try removeIfPresent(claudeDirectory)
        try FileManager.default.createDirectory(at: claudeDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: claudeDirectory.path, withDestinationPath: sharedDirectory.path)
    }

    func uninstall() throws {
        try removeIfPresent(claudeDirectory)
        try removeIfPresent(sharedDirectory)
    }

    static func version(of content: String) -> Int {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return 0 }
        for line in lines.dropFirst().prefix(while: { $0 != "---" }) {
            let field = line.trimmingCharacters(in: .whitespaces)
            guard field.hasPrefix("version:") else { continue }
            return Int(field.dropFirst("version:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))) ?? 0
        }
        return 0
    }

    private func isCurrent(_ installed: String) -> Bool {
        Self.version(of: installed) >= version
    }

    private func installedContent(in directory: URL) -> String? {
        try? String(contentsOf: directory.appending(path: Self.fileName), encoding: .utf8)
    }

    private func removeIfPresent(_ url: URL) throws {
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return }
        try FileManager.default.removeItem(atPath: url.path)
    }
}
