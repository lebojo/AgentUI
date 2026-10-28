import Foundation

struct ProjectFolder: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var sourcePath: String? = nil
}

struct TerminalRecord: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
}

struct Worktree: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var path: String
    var isPrimary = false
    var terminals: [TerminalRecord] = []
}

struct Project: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var path: String
    var folderID: UUID?
    var worktrees: [Worktree]

    init(url: URL, folderID: UUID? = nil) {
        let path = WorkspaceDisk.canonicalPath(url)
        self.name = url.lastPathComponent
        self.path = path
        self.folderID = folderID
        self.worktrees = [Worktree(name: "Principal", path: path, isPrimary: true,
                                   terminals: [TerminalRecord(name: "Terminal")])]
    }
}

struct Workspace: Codable, Equatable, Sendable {
    var version = 1
    var folders: [ProjectFolder] = []
    var projects: [Project] = []
    var selection: UUID?
    var collapsed: Set<UUID> = []
}

struct TerminalContext {
    var project: Project
    var worktree: Worktree
    var terminal: TerminalRecord
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// File operations never move or remove the user's source directories.
enum WorkspaceDisk {
    static func canonicalPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static var applicationDirectory: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return defaultApplicationDirectory
    }

    private static var defaultApplicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentUI", isDirectory: true)
    }

    static func load(from url: URL) throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let state = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        guard state.version == 1 else {
            throw WorkspaceError(message: "Cette organisation utilise une version plus récente d’AgentUI.")
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
