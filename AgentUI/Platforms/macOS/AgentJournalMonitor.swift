import Foundation

struct AgentJournal: Equatable, Sendable {
    let source: SessionChatSource
    let url: URL

    func makeReader() -> @Sendable (URL) async -> [SessionMessage] {
        switch source {
        case .claude:
            let reader = ChatJournalReader<ClaudeChatDecoder>()
            return { await reader.read($0) }
        case .codex:
            let reader = ChatJournalReader<CodexChatDecoder>()
            return { await reader.read($0) }
        case .copilot:
            let reader = ChatJournalReader<CopilotChatDecoder>()
            return { await reader.read($0) }
        case .terminal:
            return { _ in [] }
        }
    }
}

@MainActor final class AgentJournalMonitor {
    private let transcript: SessionTranscript
    private var attached: AgentJournal?
    private var read: (@Sendable (URL) async -> [SessionMessage])?
    private var fileWatch: DispatchSourceFileSystemObject?
    private var reading: Task<Void, Never>?
    private var readAgain = false
    private var generation = UUID()

    init(transcript: SessionTranscript) {
        self.transcript = transcript
    }

    func attach(_ journal: AgentJournal?) {
        guard journal != attached else { return }
        let previous = attached
        stopWatching()
        attached = journal
        guard let journal else {
            if let previous, transcript.source == previous.source { transcript.useTerminal() }
            return
        }
        read = journal.makeReader()
        transcript.useJournal([], from: journal.source)
        installFileWatch()
        scheduleRead()
    }

    private func stopWatching() {
        generation = UUID()
        fileWatch?.cancel(); fileWatch = nil
        reading?.cancel(); reading = nil
        readAgain = false
        read = nil
    }

    private func installFileWatch() {
        guard let attached else { return }
        let target = Self.nearestExistingItem(at: attached.url)
        let watchesJournal = target == attached.url
        fileWatch = FileWatch.make(target, events: [.write, .extend, .rename, .delete]) { [weak self] event in
            guard let self else { return }
            if !watchesJournal || !event.isDisjoint(with: [.rename, .delete]) {
                fileWatch?.cancel(); fileWatch = nil
                installFileWatch()
            }
            scheduleRead()
        }
    }

    private static func nearestExistingItem(at url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate = candidate.deletingLastPathComponent()
        }
        return candidate
    }

    private func scheduleRead() {
        guard let attached, let read else { return }
        if reading != nil { readAgain = true; return }
        let token = generation
        reading = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let messages = await read(attached.url)
            guard let self, !Task.isCancelled, generation == token else { return }
            reading = nil
            transcript.useJournal(messages, from: attached.source)
            if readAgain { readAgain = false; scheduleRead() }
        }
    }
}
