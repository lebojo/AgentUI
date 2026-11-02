import Foundation

struct AgentSkillInstaller: Installer {
    static let name = "agentui"
    private static let bundledContent: String? = Bundle.main.url(forResource: "SKILL", withExtension: "md")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    private static let fileName = "SKILL.md"

    let content: String
    let sharedDirectory: URL
    let claudeDirectory: URL

    init(content: String, home: URL, claudeConfiguration: URL? = nil) {
        self.content = content
        sharedDirectory = home.appending(path: ".agents/skills/\(Self.name)")
        claudeDirectory = (claudeConfiguration ?? home.appending(path: ".claude")).appending(path: "skills/\(Self.name)")
    }

    var version: Int { Self.version(of: content) }

    static func load() async throws -> AgentSkillInstaller {
        guard let content = bundledContent else { throw WorkspaceError(message: "Le skill est introuvable dans l’application.") }
        let claudeConfiguration = await LoginShell.variable("CLAUDE_CONFIG_DIR").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return AgentSkillInstaller(content: content, home: FileManager.default.homeDirectoryForCurrentUser, claudeConfiguration: claudeConfiguration)
    }

    var status: InstallationStatus {
        let versions = [sharedDirectory, claudeDirectory].map { installedContent(in: $0).map(Self.version) }
        let installed = versions.compactMap { $0 }
        guard let newest = installed.max() else { return .notInstalled }
        if newest < version { return .outdated }
        return installed.count == versions.count && installed.allSatisfy({ $0 == newest }) ? .installed : .incomplete
    }

    func install() throws {
        let newest = [installedContent(in: sharedDirectory), installedContent(in: claudeDirectory), content]
            .compactMap { $0 }
            .max { Self.version(of: $0) < Self.version(of: $1) } ?? content
        if installedContent(in: sharedDirectory) != newest {
            try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            try Data(newest.utf8).write(to: sharedDirectory.appending(path: Self.fileName), options: .atomic)
        }
        guard installedContent(in: claudeDirectory) != newest else { return }
        if itemType(at: claudeDirectory) == .typeDirectory {
            try Data(newest.utf8).write(to: claudeDirectory.appending(path: Self.fileName), options: .atomic)
            return
        }
        if itemType(at: claudeDirectory) != nil { try FileManager.default.removeItem(atPath: claudeDirectory.path) }
        try FileManager.default.createDirectory(at: claudeDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: claudeDirectory.path, withDestinationPath: sharedDirectory.path)
    }

    func uninstall() throws {
        try removeSkill(at: claudeDirectory)
        try removeSkill(at: sharedDirectory)
    }

    static func version(of content: String) -> Int {
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"])) }
        guard lines.first == "---" else { return 0 }
        for line in lines.dropFirst().prefix(while: { $0 != "---" }) where line.hasPrefix("version:") {
            let value = line.dropFirst("version:".count).prefix { $0 != "#" }
            return Int(value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))) ?? 0
        }
        return 0
    }

    private func installedContent(in directory: URL) -> String? {
        try? String(contentsOf: directory.appending(path: Self.fileName), encoding: .utf8)
    }

    private func itemType(at url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    private func removeSkill(at directory: URL) throws {
        switch itemType(at: directory) {
        case .typeSymbolicLink?:
            try FileManager.default.removeItem(atPath: directory.path)
        case .typeDirectory?:
            let skill = directory.appending(path: Self.fileName)
            if itemType(at: skill) != nil { try FileManager.default.removeItem(at: skill) }
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
                try FileManager.default.removeItem(at: directory)
            }
        default:
            return
        }
    }
}
