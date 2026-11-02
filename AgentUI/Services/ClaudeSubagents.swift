import CryptoKit
import Foundation

actor ClaudeSubagents {
    static let finishedVisibility: TimeInterval = 300
    static let abandonment: TimeInterval = 900

    private static let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]

    private var cache: [URL: Entry] = [:]

    func list(of process: AgentProcess, now: Date = .now) -> [Subagent] {
        guard process.agent == .claude, let transcriptPath = process.transcriptPath else { return [] }
        let directory = URL(fileURLWithPath: transcriptPath).deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        return list(in: directory, since: process.startedAt, now: now)
    }

    func list(in directory: URL, since start: Date, now: Date = .now) -> [Subagent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(Self.resourceKeys))) ?? []
        let journals = files.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
        let present = Set(journals)
        cache = cache.filter { $0.key.deletingLastPathComponent().path != directory.path || present.contains($0.key) }
        return journals.compactMap { subagent(journal: $0, since: start, now: now) }
            .sorted { ($0.startedAt, $0.journal.path) < ($1.startedAt, $1.journal.path) }
    }

    private func subagent(journal: URL, since start: Date, now: Date) -> Subagent? {
        guard let values = try? journal.resourceValues(forKeys: Self.resourceKeys),
              let modified = values.contentModificationDate, modified >= start else { return nil }
        let entry = entry(for: journal, modified: modified, created: values.creationDate ?? modified)
        let status = entry.status(idle: now.timeIntervalSince(modified))
        return Subagent(id: entry.id, title: entry.title, status: status, startedAt: entry.created, journal: journal,
                        isVisible: status == .working || now.timeIntervalSince(modified) < Self.finishedVisibility)
    }

    private func entry(for journal: URL, modified: Date, created: Date) -> Entry {
        let metadataURL = journal.deletingPathExtension().appendingPathExtension("meta.json")
        let metadataModified = (try? metadataURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached = cache[journal], cached.modified == modified, cached.metadataModified == metadataModified { return cached }
        let metadata = Metadata.read(metadataURL)
        let entry = Entry(id: Self.identifier(of: journal), title: metadata?.title ?? String(localized: "Subagent"),
                          created: created, modified: modified, metadataModified: metadataModified,
                          recorded: metadata?.status, endedTurn: Self.endsWithFinalAnswer(journal))
        cache[journal] = entry
        return entry
    }

    private static func identifier(of journal: URL) -> UUID {
        SHA256.hash(data: Data(journal.path.utf8)).withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    private static func endsWithFinalAnswer(_ journal: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: journal) else { return false }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(), (try? file.seek(toOffset: size > 65_536 ? size - 65_536 : 0)) != nil,
              let tail = try? file.readToEnd() else { return false }
        let lastAnswer = tail.split(separator: 10).reversed().lazy.compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]).flatMap { $0["type"] as? String == "assistant" ? $0 : nil }
        }.first
        let stopReason = (lastAnswer?["message"] as? [String: Any])?["stop_reason"] as? String
        return stopReason == "end_turn" || stopReason == "stop_sequence"
    }

    private struct Entry {
        let id: UUID
        let title: String
        let created: Date
        let modified: Date
        let metadataModified: Date?
        let recorded: SubagentStatus?
        let endedTurn: Bool

        func status(idle: TimeInterval) -> SubagentStatus {
            if let recorded, recorded != .working { return recorded }
            if endedTurn { return .done }
            return idle > ClaudeSubagents.abandonment ? .stopped : .working
        }
    }

    private struct Metadata: Decodable {
        let description: String?
        let name: String?
        let agentType: String?
        let finished: Bool?
        let stoppedByUser: Bool?

        var title: String? {
            [description, name, agentType].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }

        var status: SubagentStatus {
            if stoppedByUser == true { return .stopped }
            return finished == true ? .done : .working
        }

        static func read(_ url: URL) -> Metadata? {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) }
        }
    }
}
