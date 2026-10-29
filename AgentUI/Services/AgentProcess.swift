import Darwin
import Foundation

struct AgentProcess: Equatable, Sendable {
    let agent: ConversationAgent
    let startedAt: Date
    let directory: String
    let sessionID: String?
    var transcriptPath: String? = nil

    var transcriptTitle: String? {
        guard agent == .codex, let transcriptPath, let sessionID else { return nil }
        let rollout = URL(fileURLWithPath: transcriptPath)
        let home = (0..<4).reduce(rollout.deletingLastPathComponent()) { url, _ in url.deletingLastPathComponent() }
        let title = CodexRollout.titles(in: home.appendingPathComponent("session_index.jsonl"))[sessionID] ?? CodexRollout.read(rollout)?.firstPrompt
        return title.map { AgentConversation(agent: agent, sessionID: sessionID, title: $0, updatedAt: .now).shortTitle }
    }

    static func find(under shellPID: Int32, fallbackDirectory: String,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentProcess? {
        var pending = [shellPID]
        var visited: Set<Int32> = []
        while !pending.isEmpty, visited.count < 128 {
            let pid = pending.removeFirst()
            guard pid > 0, visited.insert(pid).inserted else { continue }
            if let agent = agent(of: pid) {
                let session = resolveSession(of: agent, in: subtree(of: pid), home: home)
                return AgentProcess(agent: agent, startedAt: startDate(of: pid) ?? .distantPast,
                                    directory: TerminalProcessDirectory.read(pid: pid) ?? fallbackDirectory,
                                    sessionID: session.id, transcriptPath: session.path)
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

    private static func agent(of pid: Int32) -> ConversationAgent? {
        let candidates = [name(of: pid)].compactMap { $0 } + Array(arguments(of: pid).prefix(2))
        let names = candidates.map { URL(fileURLWithPath: $0).lastPathComponent }
        return agent(named: names)
    }

    private static func resolveSession(of agent: ConversationAgent, in pids: [Int32], home: URL) -> (id: String?, path: String?) {
        switch agent {
        case .claude:
            struct Session: Decodable {
                let sessionId: String
            }
            let sessions = home.appendingPathComponent(".claude/sessions", isDirectory: true)
            let id = pids.lazy.compactMap { pid in
                (try? Data(contentsOf: sessions.appendingPathComponent("\(pid).json")))
                    .flatMap { try? JSONDecoder().decode(Session.self, from: $0) }?.sessionId
            }.first
            return (id, nil)
        case .codex:
            let rollout = pids.lazy.flatMap(openFiles).first { codexSessionID(inRolloutPath: $0) != nil }
            return (rollout.flatMap(codexSessionID(inRolloutPath:)), rollout)
        case .copilot:
            return (pids.lazy.flatMap(openFiles).compactMap(copilotSessionID(inPath:)).first, nil)
        case .openCode:
            return (nil, nil)
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
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let count = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var result: [String] = []
        while index < size, result.count < count {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
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
