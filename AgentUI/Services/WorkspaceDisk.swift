import Foundation

enum WorkspaceDisk {
    static var applicationDirectory: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return defaultApplicationDirectory
    }

    static var worktreesDirectory: URL {
        testWorktreesDirectory ?? storedWorktreesDirectory(in: .standard)
    }

    static var testWorktreesDirectory: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil {
            return applicationDirectory.appendingPathComponent("Worktrees", isDirectory: true)
        }
        #endif
        return nil
    }

    static let worktreesDirectoryKey = "settings.worktreesDirectory"

    static var defaultWorktreesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentui", isDirectory: true)
    }

    static func storedWorktreesDirectory(in defaults: UserDefaults) -> URL {
        defaults.string(forKey: worktreesDirectoryKey).flatMap(directory) ?? defaultWorktreesDirectory
    }

    private static func directory(_ path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private static var defaultApplicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentUI", isDirectory: true)
    }

    static func load(from url: URL) throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let state = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        guard state.version == 1 else {
            throw WorkspaceError(message: String(localized: "This organization uses a newer version of AgentUI."))
        }
        return state
    }

    static func save(_ state: Workspace, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    static func childDirectories(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])
            .filter {
                let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values.isDirectory == true && values.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
