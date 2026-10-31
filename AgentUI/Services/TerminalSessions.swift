import AppKit
import SwiftUI
import SwiftTerm
import Observation

final class ActivityTerminalView: SharedProcessTerminalView {
    private(set) var lastOutput = Date.distantPast

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutput = .now
        super.dataReceived(slice: slice)
    }

    var visibleLines: [String] {
        let terminal = getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }
}

@MainActor @Observable final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let view: ActivityTerminalView
    private(set) var hasExited = false
    private(set) var exitCode: Int32?
    private(set) var title = ""
    let path: String
    let identity = UUID()
    let transcript = SessionTranscript()
    private(set) var outputRevision = 0
    private(set) var isLaunchingAgent = false
    @ObservationIgnored private let runsShell: Bool
    @ObservationIgnored private var mirrorModes = TerminalMirrorModes()
    @ObservationIgnored private var cachedScreen: TerminalScreen?
    @ObservationIgnored private var screenRevision = -1
    @ObservationIgnored private var transcriptRevision = -1
    @ObservationIgnored private lazy var journalMonitor = AgentJournalMonitor(transcript: transcript)
    @ObservationIgnored private var chatViewers = 0
    @ObservationIgnored private var chatRelease: Task<Void, Never>?
    @ObservationIgnored private var pendingWrite: Task<Void, Error>?

    private(set) var currentDirectory: String
    private(set) var branch: GitBranch?
    private(set) var agent: AgentProcess?
    private(set) var agentStatus: AgentStatus?

    init(context: TerminalContext, command: [String], environment: [String: String]) {
        path = context.worktree.path
        currentDirectory = context.worktree.path
        runsShell = command.isEmpty
        view = ActivityTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        view.processDelegate = self
        view.received = { [weak self] data in
            guard let self else { return }
            self.mirrorModes.append(data)
            self.outputRevision += 1
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            hasExited = true
            view.feed(text: "Le dossier n’est plus accessible :\r\n\(path)\r\n")
            return
        }
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "AgentUI"
        env["AGENTUI_PROJECT_ID"] = context.project.id.uuidString
        env["AGENTUI_WORKTREE_ID"] = context.worktree.id.uuidString
        env["AGENTUI_TERMINAL_ID"] = context.terminal.id.uuidString
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        let configuredShell = env["SHELL"] ?? "/bin/zsh"
        let shell = FileManager.default.isExecutableFile(atPath: configuredShell) ? configuredShell : "/bin/zsh"
        let args = command.isEmpty ? ["-l"] : ["-l", "-i", "-c", "exec \"$@\"", "agentui"] + command
        view.startProcess(executable: shell, args: args, environment: env.map { "\($0.key)=\($0.value)" }, currentDirectory: path)
        if !view.process.running {
            hasExited = true
            view.feed(text: "Impossible de démarrer le terminal.\r\n")
        }
    }

    func acquireChat() {
        chatViewers += 1
        chatRelease?.cancel()
        chatRelease = nil
        journalMonitor.attach(agent?.journal)
    }

    func releaseChat() {
        chatViewers = max(0, chatViewers - 1)
        guard chatViewers == 0 else { return }
        chatRelease = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, chatViewers == 0 else { return }
            chatRelease = nil
            journalMonitor.attach(nil)
        }
    }

    func updateTranscript() {
        guard transcript.source == .terminal, (transcriptRevision != outputRevision || transcript.messages.isEmpty) else { return }
        transcriptRevision = outputRevision
        transcript.update(screen: view.getTerminal().recentText(limit: 65_536))
    }

    func send(_ data: Data, message: String? = nil) async throws {
        guard data.count <= 65_536 else { throw WorkspaceError(message: "Message trop long (64 Ko maximum).") }
        let previous = pendingWrite
        let write = Task {
            _ = await previous?.result
            try await write(data, message: message)
        }
        pendingWrite = write
        try await write.value
    }

    func launch(_ agent: ConversationAgent, skippingPermissions: Bool) async throws {
        guard self.agent == nil, !isLaunchingAgent, isShellInForeground else {
            throw WorkspaceError(message: "Le terminal n’est pas à l’invite du shell. Termine la commande en cours avant de lancer un agent.")
        }
        isLaunchingAgent = true
        defer { isLaunchingAgent = false }
        let command = agent.launchCommand(skippingPermissions: skippingPermissions).joined(separator: " ")
        try await send(Data((command + "\r").utf8))
        try await waitForForegroundCommand()
    }

    private var isShellInForeground: Bool {
        runsShell && !hasExited && tcgetpgrp(view.process.childfd) == view.process.shellPid
    }

    private func waitForForegroundCommand() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while isShellInForeground, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func write(_ data: Data, message: String?) async throws {
        guard !hasExited else { throw WorkspaceError(message: "Cette session est terminée.") }
        guard let message else {
            view.send(source: view, data: Array(data)[...])
            return
        }
        updateTranscript()
        transcript.sent(message)
        if data.last == 13, view.getTerminal().bracketedPasteMode {
            try await submitAsSinglePaste(data.dropLast())
        } else {
            view.send(source: view, data: Array(data)[...])
        }
    }

    private func submitAsSinglePaste(_ text: Data) async throws {
        var paste = Data("\u{1b}[200~".utf8)
        paste.append(text)
        paste.append(Data("\u{1b}[201~".utf8))
        view.send(source: view, data: Array(paste)[...])
        try await Task.sleep(for: .milliseconds(50))
        guard !hasExited else { throw WorkspaceError(message: "Cette session est terminée.") }
        view.send(source: view, data: [13][...])
    }

    func screen() -> TerminalScreen {
        let terminal = view.getTerminal()
        if let cachedScreen, screenRevision == outputRevision, cachedScreen.columns == terminal.cols, cachedScreen.rows == terminal.rows {
            return cachedScreen
        }
        let screen = TerminalScreen(terminal: terminal, modes: mirrorModes, previous: cachedScreen)
        cachedScreen = screen
        screenRevision = outputRevision
        return screen
    }

    func snapshot(previousMessages: [SessionMessage], chat: Bool,
                  screen: TerminalScreen? = nil, previousScreen: TerminalScreen? = nil) -> RemoteTerminalSnapshot {
        let bytes = chat ? (data: Data(), reset: false) : (screen ?? self.screen()).output(after: previousScreen)
        let messages = chat ? transcript.messages : []
        let delta = SessionTranscriptDelta(previous: previousMessages, current: messages)
        let terminal = view.getTerminal()
        return RemoteTerminalSnapshot(identity: identity, isChat: chat, output: bytes.data, reset: bytes.reset,
                                      columns: terminal.cols, rows: terminal.rows,
                                      transcript: delta.messages, transcriptDropped: delta.dropped, transcriptStart: delta.start,
                                      transcriptAppend: delta.append,
                                      hasExited: hasExited, exitCode: exitCode, chatSource: transcript.source)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { outputRevision += 1 }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { self.title = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasExited = true
        journalMonitor.attach(nil)
        self.exitCode = exitCode.flatMap { $0 & 0x7f == 0 ? ($0 >> 8) & 0xff : nil }
    }
    func updateRepository(directory: String, branch: GitBranch?) {
        if currentDirectory != directory { currentDirectory = directory }
        if self.branch != branch { self.branch = branch }
    }

    func updateAgent(_ process: AgentProcess?) {
        let running = hasExited ? nil : process?.keepingTranscript(of: agent)
        let status = running.map { process in
            process.claudeStatus.flatMap(AgentStatus.init(claudeStatus:))
                ?? AgentStatus(screen: view.visibleLines, lastOutput: view.lastOutput)
        }
        if agent != running { agent = running }
        if agentStatus != status { agentStatus = status }
        if chatViewers > 0 || chatRelease != nil { journalMonitor.attach(running?.journal) }
    }

    func stop() {
        journalMonitor.attach(nil)
        guard view.process.running else { return }
        let pid = view.process.shellPid
        if pid > 0 { kill(-pid, SIGHUP) }
        view.terminate()
    }
}

@MainActor @Observable final class TerminalSessions {
    private var entries: [UUID: TerminalSession] = [:]
    var environment: [String: String] = [:]
    private(set) var branchesByPath: [String: GitBranch] = [:]
    @ObservationIgnored private var refreshingRepositories = false
    @ObservationIgnored private var refreshingAgents = false
    @ObservationIgnored private var lastAgentRefresh: ContinuousClock.Instant?

    func branch(for terminalID: UUID, initialPath: String) -> GitBranch? {
        if let session = entries[terminalID] { return session.branch }
        return branchesByPath[initialPath]
    }

    func refreshRepositories(worktreePaths: [String]) async {
        guard !refreshingRepositories else { return }
        refreshingRepositories = true
        defer { refreshingRepositories = false }
        let locations = entries.map { id, session in
            Location(id: id, identity: session.identity, pid: session.hasExited ? 0 : session.view.process.shellPid,
                     fallback: session.currentDirectory)
        }
        let result = await Self.inspect(worktreePaths: worktreePaths, locations: locations)
        guard !Task.isCancelled else { return }
        if branchesByPath != result.branches { branchesByPath = result.branches }
        for value in result.sessions {
            guard let session = entries[value.id], session.identity == value.identity else { continue }
            session.updateRepository(directory: value.directory, branch: value.branch)
        }
    }

    private struct Location: Sendable {
        let id: UUID
        let identity: UUID
        let pid: Int32
        let fallback: String
    }

    private struct SessionRepository: Sendable {
        let id: UUID
        let identity: UUID
        let directory: String
        let branch: GitBranch?
    }

    @concurrent nonisolated private static func inspect(worktreePaths: [String], locations: [Location]) async -> (branches: [String: GitBranch], sessions: [SessionRepository]) {
        var cache: [String: GitBranch?] = [:]
        func branch(at path: String) -> GitBranch? {
            if let cached = cache[path] { return cached }
            let value = GitRepository.containing(path)?.branch
            cache[path] = .some(value)
            return value
        }
        var branches: [String: GitBranch] = [:]
        for path in Set(worktreePaths) { branches[path] = branch(at: path) }
        let sessions = locations.map { location in
            let directory = TerminalProcessDirectory.read(pid: location.pid) ?? location.fallback
            return SessionRepository(id: location.id, identity: location.identity, directory: directory, branch: branch(at: directory))
        }
        return (branches, sessions)
    }

    func refreshAgents() async {
        guard !refreshingAgents, lastAgentRefresh.map({ $0.duration(to: .now) >= .milliseconds(900) }) ?? true else { return }
        refreshingAgents = true
        lastAgentRefresh = .now
        defer { refreshingAgents = false }
        let shells = entries.compactMap { id, session in
            session.hasExited ? nil : (id: id, identity: session.identity, pid: session.view.process.shellPid, directory: session.currentDirectory)
        }
        let found = await Task.detached(priority: .utility) {
            shells.reduce(into: [UUID: AgentProcess]()) { result, shell in
                result[shell.identity] = AgentProcess.find(under: shell.pid, fallbackDirectory: shell.directory)
            }
        }.value
        guard !Task.isCancelled else { return }
        for session in entries.values { session.updateAgent(found[session.identity]) }
    }

    func conversationTitles() async -> [UUID: String] {
        let processes = entries.compactMapValues(\.agent)
        guard !processes.isEmpty else { return [:] }
        var conversations: [String: [AgentConversation]] = [:]
        for directory in Set(processes.values.map(\.directory)) {
            conversations[directory] = await ConversationIndex.shared.conversations(at: directory)
        }
        let titles = AgentProcess.titles(for: processes, conversations: conversations)
        let unresolved = processes.filter { titles[$0.key] == nil && $0.value.transcriptPath != nil }
        guard !unresolved.isEmpty else { return titles }
        return await Task.detached(priority: .utility) {
            unresolved.reduce(into: titles) { result, entry in result[entry.key] = entry.value.transcriptTitle }
        }.value
    }

    var runningCount: Int { entries.values.filter { !$0.hasExited }.count }

    func session(_ id: UUID) -> TerminalSession? { entries[id] }
    @discardableResult func start(_ context: TerminalContext, command: [String] = []) -> TerminalSession {
        if let session = entries[context.terminal.id] { return session }
        let session = TerminalSession(context: context, command: command, environment: environment)
        entries[context.terminal.id] = session
        return session
    }
    func close(_ id: UUID) { entries.removeValue(forKey: id)?.stop() }
    func stopAll() {
        for session in entries.values { session.stop() }
        entries.removeAll()
    }
}

struct NativeTerminalView: NSViewRepresentable {
    final class Coordinator {
        var appliedAppearance: TerminalAppearance?
        var appliedColorScheme: ColorScheme?
        var wasFocused = false
        var focus: () -> Void = {}
        var mouseMonitor: Any?
    }

    let session: TerminalSession
    let appearance: TerminalAppearance
    let isFocused: Bool
    let focus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.setAccessibilityLabel("Terminal interactif")
        let terminal = session.view
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            terminal.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            terminal.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8)
        ])
        applyAppearance(context: context)
        let coordinator = context.coordinator
        coordinator.focus = focus
        coordinator.wasFocused = isFocused
        coordinator.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak host] event in
            if let host, event.window === host.window, host.bounds.contains(host.convert(event.locationInWindow, from: nil)) {
                coordinator.focus()
            }
            return event
        }
        if isFocused { DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) } }
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        applyAppearance(context: context)
        context.coordinator.focus = focus
        if isFocused, !context.coordinator.wasFocused {
            let terminal = session.view
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
        context.coordinator.wasFocused = isFocused
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.mouseMonitor { NSEvent.removeMonitor(monitor) }
        coordinator.mouseMonitor = nil
    }

    private func applyAppearance(context: Context) {
        let colorScheme = context.environment.colorScheme
        guard context.coordinator.appliedAppearance != appearance || context.coordinator.appliedColorScheme != colorScheme else { return }
        context.coordinator.appliedAppearance = appearance
        context.coordinator.appliedColorScheme = colorScheme
        session.view.apply(appearance)
    }
}

private extension AgentProcess {
    var journal: AgentJournal? {
        switch agent {
        case .claude:
            transcriptPath.map { AgentJournal(source: .claude, url: URL(fileURLWithPath: $0)) }
        case .codex:
            transcriptPath.map { AgentJournal(source: .codex, url: URL(fileURLWithPath: $0)) }
        case .copilot:
            transcriptPath.map { AgentJournal(source: .copilot, url: URL(fileURLWithPath: $0)) }
        case .openCode:
            nil
        }
    }
}
