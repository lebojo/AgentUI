import Foundation

actor ConversationIndex {
    static let shared = ConversationIndex()

    private struct Stamp: Equatable {
        let modified: Date
        let size: Int
    }

    private struct Cached<Value> {
        let stamp: Stamp
        let value: Value
    }

    private let home: URL
    private var claudeCache: [String: Cached<ClaudeTranscript>] = [:]
    private var codexCache: [String: Cached<CodexRollout?>] = [:]
    private var copilotCache: [String: Cached<CopilotWorkspace?>] = [:]
    private var copilotPromptCache: [String: Cached<String?>] = [:]
    private var openCodeCache: (stamps: [Stamp?], sessions: [OpenCodeSessions.Session])?
    private var runningCache: [String: (checked: ContinuousClock.Instant, sessions: Set<String>)] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    static var watchedDirectories: [String] { shared.watchedDirectories }

    nonisolated var watchedDirectories: [String] {
        [".claude/projects", ".codex/sessions", ".copilot/session-state", ".local/share/opencode"]
            .map { home.appendingPathComponent($0, isDirectory: true).path }
    }

    static func load(at path: String, runningMaximumAge: Duration = .seconds(10)) async -> [AgentConversation] {
        async let running = shared.runningSessions(at: path, maximumAge: runningMaximumAge)
        let conversations = await shared.conversations(at: path)
        let active = await running
        return conversations.map { conversation in
            var conversation = conversation
            conversation.isRunning = conversation.agent == .claude && active.contains(conversation.sessionID)
            return conversation
        }
    }

    func conversations(at path: String) -> [AgentConversation] {
        (claudeConversations(at: path) + codexConversations(at: path) + copilotConversations(at: path) + openCodeConversations(at: path))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func claudeDirectoryName(for path: String) -> String {
        String(path.unicodeScalars.map { $0.isASCII && CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" })
    }

    static func samePath(_ recorded: String?, _ path: String) -> Bool {
        recorded?.compare(path, options: .caseInsensitive) == .orderedSame
    }

    private func claudeConversations(at path: String) -> [AgentConversation] {
        claudeDirectories(for: path).flatMap { directory in
            Self.contents(of: directory).filter { $0.pathExtension == "jsonl" }.compactMap { url -> AgentConversation? in
                guard let stamp = Self.stamp(url) else { return nil }
                let transcript = cached(url, stamp: stamp, in: &claudeCache) { ClaudeTranscript.read(url) }
                guard Self.samePath(transcript.cwd, path), let title = transcript.title else { return nil }
                return AgentConversation(agent: .claude, sessionID: url.deletingPathExtension().lastPathComponent,
                                         title: title, updatedAt: stamp.modified)
            }
        }
    }

    private func claudeDirectories(for path: String) -> [URL] {
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let name = Self.claudeDirectoryName(for: path)
        let exact = projects.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: exact.path) { return [exact] }
        guard name.count > 200 else { return [] }
        let prefix = String(name.prefix(200))
        return Self.contents(of: projects).filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func codexConversations(at path: String) -> [AgentConversation] {
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let rollouts = enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
        var found: [String: AgentConversation] = [:]
        var titles: [String: String]?
        for url in rollouts {
            guard let stamp = Self.stamp(url),
                  let rollout = cached(url, stamp: stamp, in: &codexCache, read: { CodexRollout.read(url) }),
                  Self.samePath(rollout.cwd, path) else { continue }
            if titles == nil { titles = CodexRollout.titles(in: codex.appendingPathComponent("session_index.jsonl")) }
            if let existing = found[rollout.sessionID], existing.updatedAt >= stamp.modified { continue }
            let title = titles?[rollout.sessionID] ?? rollout.firstPrompt ?? "Conversation Codex"
            found[rollout.sessionID] = AgentConversation(agent: .codex, sessionID: rollout.sessionID, title: title, updatedAt: stamp.modified)
        }
        return Array(found.values)
    }

    private func copilotConversations(at path: String) -> [AgentConversation] {
        let sessions = home.appendingPathComponent(".copilot/session-state", isDirectory: true)
        var found: [AgentConversation] = []
        for directory in Self.contents(of: sessions) {
            let workspaceURL = directory.appendingPathComponent("workspace.yaml")
            let events = directory.appendingPathComponent("events.jsonl")
            guard let workspaceStamp = Self.stamp(workspaceURL),
                  let workspace = cached(workspaceURL, stamp: workspaceStamp, in: &copilotCache, read: { CopilotWorkspace.read(workspaceURL) }),
                  Self.samePath(workspace.cwd, path) else { continue }
            let eventsStamp = Self.stamp(events)
            var title = workspace.title
            if title == nil, let eventsStamp {
                title = cached(events, stamp: eventsStamp, in: &copilotPromptCache) { CopilotWorkspace.firstPrompt(in: events) }
            }
            let updatedAt = max(workspaceStamp.modified, eventsStamp?.modified ?? .distantPast)
            found.append(AgentConversation(agent: .copilot, sessionID: directory.lastPathComponent,
                                           title: title ?? "Conversation Copilot", updatedAt: updatedAt))
        }
        return found
    }

    private func openCodeConversations(at path: String) -> [AgentConversation] {
        var found: [String: AgentConversation] = [:]
        for session in openCodeSessions() where Self.samePath(session.directory, path) {
            if let existing = found[session.id], existing.updatedAt >= session.updatedAt { continue }
            let title = ConversationTitle.clean(session.title) ?? "Conversation OpenCode"
            found[session.id] = AgentConversation(agent: .openCode, sessionID: session.id, title: title, updatedAt: session.updatedAt)
        }
        return Array(found.values)
    }

    private func openCodeSessions() -> [OpenCodeSessions.Session] {
        let database = home.appendingPathComponent(".local/share/opencode/opencode.db")
        let stamps = [database, URL(fileURLWithPath: database.path + "-wal")].map(Self.stamp)
        if let openCodeCache, openCodeCache.stamps == stamps { return openCodeCache.sessions }
        guard let sessions = OpenCodeSessions.read(database) else { return openCodeCache?.sessions ?? [] }
        openCodeCache = (stamps, sessions)
        return sessions
    }

    private func cached<Value>(_ url: URL, stamp: Stamp, in cache: inout [String: Cached<Value>], read: () -> Value) -> Value {
        if let entry = cache[url.path], entry.stamp == stamp { return entry.value }
        let value = read()
        cache[url.path] = Cached(stamp: stamp, value: value)
        return value
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])) ?? []
    }

    private static func stamp(_ url: URL) -> Stamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let modified = values.contentModificationDate else { return nil }
        return Stamp(modified: modified, size: values.fileSize ?? 0)
    }

    func runningSessions(at path: String, maximumAge: Duration) async -> Set<String> {
        if let cached = runningCache[path], cached.checked.duration(to: .now) < maximumAge { return cached.sessions }
        let sessions = await Self.runningClaudeSessions(at: path)
        runningCache[path] = (.now, sessions)
        return sessions
    }

    private static func runningClaudeSessions(at path: String) async -> Set<String> {
        struct Session: Decodable {
            let sessionId: String
        }
        guard let claude = ReadCommand.executable("claude"),
              let data = try? await ReadCommand.run(claude, ["agents", "--json", "--cwd", path], at: path, timeout: 5),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else { return [] }
        return Set(sessions.map(\.sessionId))
    }
}
