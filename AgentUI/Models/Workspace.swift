import Foundation

struct ProjectFolder: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var sourcePath: String? = nil
    var parentID: UUID? = nil
    var symbol: SidebarSymbol? = nil
    var tint: SidebarTint? = nil

    var appearance: SidebarAppearance { SidebarAppearance(kind: .folder, symbol: symbol, tint: tint) }
}

struct TerminalRecord: Identifiable, Codable, Equatable, Sendable {
    static let defaultName = "Terminal"

    var id = UUID()
    var name: String
    var hasCustomName = false
    var resume: AgentResume? = nil
}

extension TerminalRecord {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let automaticNames = [Self.defaultName] + ConversationAgent.allCases.map(\.title)
        hasCustomName = try container.decodeIfPresent(Bool.self, forKey: .hasCustomName) ?? !automaticNames.contains(name)
        resume = try? container.decodeIfPresent(AgentResume.self, forKey: .resume)
    }
}

struct WorktreeGroup: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
}

struct Worktree: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var path: String
    var isPrimary = false
    var terminals: [TerminalRecord] = []
    var groupID: UUID? = nil
    var layouts: [TerminalLayout] = []

    var displayName: String { isPrimary ? String(localized: "Main") : name }

    func layout(containing terminalID: UUID) -> TerminalLayout? {
        layouts.first { $0.contains(terminalID) }
    }
}

extension Worktree {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        terminals = try container.decode([TerminalRecord].self, forKey: .terminals)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        layouts = try container.decodeIfPresent([TerminalLayout].self, forKey: .layouts) ?? []
    }
}

struct Project: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var path: String
    var folderID: UUID?
    var worktrees: [Worktree]
    var symbol: SidebarSymbol? = nil
    var tint: SidebarTint? = nil
    var worktreeGroups: [WorktreeGroup] = []

    var appearance: SidebarAppearance { SidebarAppearance(kind: .project, symbol: symbol, tint: tint) }

    func worktrees(in groupID: UUID?) -> [Worktree] {
        worktrees.filter { !$0.isPrimary && $0.groupID == groupID }
    }

    init(url: URL, folderID: UUID? = nil) {
        let path = WorkspacePath.canonical(url)
        self.name = url.lastPathComponent
        self.path = path
        self.folderID = folderID
        self.worktrees = [Worktree(name: "Main", path: path, isPrimary: true,
                                   terminals: [TerminalRecord(name: "Terminal")])]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        worktrees = try container.decode([Worktree].self, forKey: .worktrees)
        symbol = try container.decodeIfPresent(SidebarSymbol.self, forKey: .symbol)
        tint = try container.decodeIfPresent(SidebarTint.self, forKey: .tint)
        worktreeGroups = try container.decodeIfPresent([WorktreeGroup].self, forKey: .worktreeGroups) ?? []
    }
}

struct Workspace: Codable, Equatable, Sendable {
    var version = 1
    var folders: [ProjectFolder] = []
    var projects: [Project] = []
    var selection: UUID?
    var collapsed: Set<UUID> = []
}

extension Workspace {
    func location(containing directory: String) -> (projectID: UUID, worktreeID: UUID)? {
        let matches = projects.flatMap { project in
            project.worktrees.filter { directory == $0.path || directory.hasPrefix($0.path + "/") }.map { (project, $0) }
        }
        guard let (project, worktree) = matches.max(by: { $0.1.path.count < $1.1.path.count }) else { return nil }
        return (project.id, worktree.id)
    }
}

struct FolderDestination: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
}

extension [ProjectFolder] {
    func isRoot(_ folder: ProjectFolder) -> Bool {
        guard let parentID = folder.parentID else { return true }
        return !contains { $0.id == parentID }
    }

    func children(of parentID: UUID?) -> [ProjectFolder] {
        guard let parentID else { return filter(isRoot) }
        return filter { $0.parentID == parentID }
    }

    func ancestors(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var current = first { $0.id == id }?.parentID
        while let parentID = current, !result.contains(parentID), let parent = first(where: { $0.id == parentID }) {
            result.append(parentID)
            current = parent.parentID
        }
        return result
    }

    func subtree(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var pending = [id]
        while let parentID = pending.popLast() {
            for child in children(of: parentID) where result.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return result
    }

    func destinations(excluding excludedID: UUID? = nil) -> [FolderDestination] {
        let excluded = excludedID.map(subtree) ?? []
        func walk(_ parentID: UUID?, prefix: String) -> [FolderDestination] {
            children(of: parentID).filter { !excluded.contains($0.id) }.flatMap { folder in
                let title = prefix + folder.name
                return [FolderDestination(id: folder.id, title: title)] + walk(folder.id, prefix: title + " › ")
            }
        }
        return walk(nil, prefix: "")
    }
}

struct TerminalContext: Equatable, Sendable {
    struct ProjectInfo: Equatable, Sendable {
        let id: UUID
        let name: String
    }

    struct WorktreeInfo: Equatable, Sendable {
        let id: UUID
        let name: String
        let path: String
        let isPrimary: Bool
    }

    let project: ProjectInfo
    let worktree: WorktreeInfo
    let terminal: TerminalRecord

    init(project: Project, worktree: Worktree, terminal: TerminalRecord) {
        self.project = ProjectInfo(id: project.id, name: project.name)
        self.worktree = WorktreeInfo(id: worktree.id, name: worktree.displayName, path: worktree.path, isPrimary: worktree.isPrimary)
        self.terminal = terminal
    }

    init?(terminalID: UUID?, in projects: [Project]) {
        for project in projects {
            for worktree in project.worktrees {
                if let terminal = worktree.terminals.first(where: { $0.id == terminalID }) {
                    self.init(project: project, worktree: worktree, terminal: terminal)
                    return
                }
            }
        }
        return nil
    }
}

struct WorkspaceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum WorkspacePath {
    static func canonical(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
