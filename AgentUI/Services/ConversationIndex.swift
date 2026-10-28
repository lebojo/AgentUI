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

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    static func load(at path: String) async -> [AgentConversation] {
        async let running = runningClaudeSessions(at: path)
        let conversations = await shared.conversations(at: path)
        let active = await running
        return conversations.map { conversation in
            var conversation = conversation
            conversation.isRunning = conversation.agent == .claude && active.contains(conversation.sessionID)
            return conversation
        }
    }

    func conversations(at path: String) -> [AgentConversation] {
        (claudeConversations(at: path) + codexConversations(at: path)).sorted { $0.updatedAt > $1.updatedAt }
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
