import Darwin
import Foundation

struct AgentProcess: Equatable, Sendable {
    let agent: ConversationAgent
    let startedAt: Date
    let directory: String
    let sessionID: String?
    var transcriptPath: String? = nil
    var claudeStatus: String? = nil

    var transcriptTitle: String? {
        guard agent == .codex, let transcriptPath, let sessionID else { return nil }
        let rollout = URL(fileURLWithPath: transcriptPath)
        let home = (0..<4).reduce(rollout.deletingLastPathComponent()) { url, _ in url.deletingLastPathComponent() }
        let title = CodexRollout.titles(in: home.appendingPathComponent("session_index.jsonl"))[sessionID] ?? CodexRollout.read(rollout)?.firstPrompt
        return title.map { AgentConversation(agent: agent, sessionID: sessionID, title: $0, updatedAt: .now).shortTitle }
    }

    func keepingTranscript(of previous: AgentProcess?) -> AgentProcess {
        guard transcriptPath == nil, let previous, previous.agent == agent, previous.startedAt == startedAt,
              sessionID == nil || sessionID == previous.sessionID else { return self }
        return AgentProcess(agent: agent, startedAt: startedAt, directory: directory, sessionID: previous.sessionID,
                            transcriptPath: previous.transcriptPath, claudeStatus: claudeStatus ?? previous.claudeStatus)
    }

    static func find(under shellPID: Int32, fallbackDirectory: String, previous: AgentProcess? = nil,
                     claudeConfig: URL = ClaudeTranscript.configDirectory()) -> AgentProcess? {
        var pending = [shellPID]
        var visited: Set<Int32> = []
        while !pending.isEmpty, visited.count < 128 {
            let pid = pending.removeFirst()
            guard pid > 0, visited.insert(pid).inserted else { continue }
            if let agent = agent(of: pid) {
                let config = agent == .claude ? processClaudeConfig(of: pid) ?? claudeConfig : claudeConfig
                let session = resolveSession(of: agent, in: subtree(of: pid), claudeConfig: config, previous: previous)
                return AgentProcess(agent: agent, startedAt: startDate(of: pid) ?? .distantPast,
                                    directory: TerminalProcessDirectory.read(pid: pid) ?? fallbackDirectory,
                                    sessionID: session.id, transcriptPath: session.path, claudeStatus: session.status)
            }
            pending += children(of: pid)
        }
        return nil
    }

    static func titles(for processes: [UUID: AgentProcess], conversations: [String: [AgentConversation]]) -> [UUID: String] {
        var titles: [UUID: String] = [:]
        var claimed: Set<String> = []
        for (terminalID, process) in processes {
            guard let sessionID = process.sessionID,
                  let conversation = conversations[process.directory]?.first(where: { $0.agent == process.agent && $0.sessionID == sessionID }) else { continue }
            titles[terminalID] = conversation.shortTitle
            claimed.insert(conversation.id)
        }
        let unresolved = processes.filter { titles[$0.key] == nil }.sorted { $0.value.startedAt > $1.value.startedAt }
        for (terminalID, process) in unresolved {
            let earliest = process.startedAt.addingTimeInterval(-2)
            let candidates = (conversations[process.directory] ?? []).filter { conversation in
                guard conversation.agent == process.agent, !claimed.contains(conversation.id) else { return false }
                guard process.sessionID == nil || conversation.sessionID == process.sessionID else { return false }
                return conversation.updatedAt >= earliest
            }
            guard let conversation = candidates.max(by: { $0.updatedAt < $1.updatedAt }) else { continue }
            titles[terminalID] = conversation.shortTitle
            claimed.insert(conversation.id)
        }
        return titles
    }

    static func agent(named names: [String]) -> ConversationAgent? {
        ConversationAgent.allCases.first { agent in names.contains(agent.rawValue) }
    }

    static func codexSessionID(inRolloutPath path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
        let identifier = String(name.dropLast(6).suffix(36))
        return UUID(uuidString: identifier) == nil ? nil : identifier
    }

    static func copilotSessionID(inPath path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let index = components.firstIndex(of: "session-state"), index > 0, components[index - 1] == ".copilot",
              index + 1 < components.count else { return nil }
        return components[index + 1]
    }

    static func copilotJournalPath(inPath path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let index = components.firstIndex(of: "session-state"), index + 1 < components.count,
              copilotSessionID(inPath: path) != nil else { return nil }
        return (components[...(index + 1)] + ["events.jsonl"]).joined(separator: "/")
    }

    private static func agent(of pid: Int32) -> ConversationAgent? {
        let candidates = [name(of: pid)].compactMap { $0 } + Array(arguments(of: pid).prefix(2))
        let names = candidates.map { URL(fileURLWithPath: $0).lastPathComponent }
        return agent(named: names)
    }

    private static func resolveSession(of agent: ConversationAgent, in pids: [Int32], claudeConfig: URL,
                                       previous: AgentProcess?) -> (id: String?, path: String?, status: String?) {
        switch agent {
        case .claude:
            let sessions = claudeConfig.appendingPathComponent("sessions", isDirectory: true)
            let session = pids.lazy.compactMap { pid in
                (try? Data(contentsOf: sessions.appendingPathComponent("\(pid).json")))
                    .flatMap { try? JSONDecoder().decode(ClaudeSession.self, from: $0) }
            }.first
            guard let session else { return (nil, nil, nil) }
            if previous?.agent == .claude, previous?.sessionID == session.sessionId, let known = previous?.transcriptPath,
               FileManager.default.fileExists(atPath: known) {
                return (session.sessionId, known, session.status)
            }
            let projects = claudeConfig.appendingPathComponent("projects", isDirectory: true)
            return (session.sessionId, session.transcript(in: projects)?.path, session.status)
        case .codex:
            let rollout = pids.lazy.flatMap(openFiles).first { codexSessionID(inRolloutPath: $0) != nil }
            return (rollout.flatMap(codexSessionID(inRolloutPath:)), rollout, nil)
        case .copilot:
            let file = pids.lazy.flatMap(openFiles).first { copilotSessionID(inPath: $0) != nil }
            return (file.flatMap(copilotSessionID(inPath:)), file.flatMap(copilotJournalPath(inPath:)), nil)
        case .openCode:
            return (nil, nil, nil)
        }
    }

    private struct ClaudeSession: Decodable {
        let sessionId: String
        let status: String?
        let cwd: String?

        func transcript(in projects: URL) -> URL? {
            guard let cwd, UUID(uuidString: sessionId) != nil else { return nil }
            return ClaudeTranscript.url(sessionID: sessionId, cwd: cwd, projects: projects)
        }
    }

    private static func subtree(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var pending = [pid]
        while let current = pending.popLast(), result.count < 128 {
            guard !result.contains(current) else { continue }
            result.append(current)
            pending += children(of: current)
        }
        return result
    }

    private static func children(of pid: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 256)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        return buffer.prefix(Int(bytes) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    private static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func arguments(of pid: Int32) -> [String] {
        commandLine(of: pid, includingEnvironment: false).arguments
    }

    private static func processClaudeConfig(of pid: Int32) -> URL? {
        let prefix = "CLAUDE_CONFIG_DIR="
        guard let value = commandLine(of: pid, includingEnvironment: true).environment.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count), value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: String(value))
    }

    private static func commandLine(of pid: Int32, includingEnvironment: Bool) -> (arguments: [String], environment: [String]) {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ([], []) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return ([], []) }
        let count = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var strings: [String] = []
        while index < size, includingEnvironment || strings.count < count {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            guard index > start || strings.count < count else { break }
            strings.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return (Array(strings.prefix(count)), Array(strings.dropFirst(count)))
    }

    private static func startDate(of pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    private static func openFiles(of pid: Int32) -> [String] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 16)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
        guard filled > 0 else { return [] }
        return descriptors.prefix(Int(filled) / stride).compactMap { descriptor in
            guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
            return withUnsafePointer(to: &info.pvip.vip_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        }
    }
}
