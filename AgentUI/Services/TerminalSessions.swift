import AppKit
import SwiftTerm
import Observation

@MainActor @Observable final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, TerminalOutputReceiver {
    enum InputOrigin: Sendable {
        case local
        case remote
    }

    let view: ActivityTerminalView
    private(set) var hasExited = false
    private(set) var exitCode: Int32?
    private(set) var title = ""
    let path: String
    let terminalID: UUID
    let isFloating: Bool
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
    @ObservationIgnored private var transcriptRefresh: Task<Void, Never>?
    @ObservationIgnored private var pendingWrite: Task<Void, Error>?

    private(set) var currentDirectory: String
    private(set) var branch: GitBranch?
    private(set) var divergentBranch: GitBranch?
    private(set) var agent: AgentProcess?
    private(set) var agentKind: ConversationAgent?
    private(set) var agentStatus: AgentStatus?
    private(set) var subagents: [Subagent] = []
    @ObservationIgnored private(set) var hadAgent = false
    @ObservationIgnored var resume: AgentResume?
    @ObservationIgnored fileprivate weak var owner: TerminalSessions?
    fileprivate(set) var remoteGrid: TerminalGridSize? {
        didSet { view.remoteGrid = remoteGrid }
    }

    init(context: TerminalContext, command: [String], keepsShell: Bool = false, environment: [String: String]) {
        path = context.worktree.path
        terminalID = context.terminal.id
        isFloating = context.isFloating
        currentDirectory = context.worktree.path
        runsShell = command.isEmpty
        view = ActivityTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        view.processDelegate = self
        view.outputReceiver = self
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            hasExited = true
            view.feed(text: String(localized: "The folder is no longer accessible:") + "\r\n\(path)\r\n")
            return
        }
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "AgentUI"
        let workspaceContext = context.isFloating ? nil : context
        env["AGENTUI_PROJECT_ID"] = workspaceContext?.project.id.uuidString
        env["AGENTUI_WORKTREE_ID"] = workspaceContext?.worktree.id.uuidString
        env["AGENTUI_TERMINAL_ID"] = workspaceContext?.terminal.id.uuidString
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        let shell = LoginShell.path(environment: env)
        let args = if command.isEmpty { ["-l"] }
            else if keepsShell { ["-l", "-i", "-c", "\"$@\"; exec \"$0\" -l", shell] + command }
            else { ["-l", "-i", "-c", "exec \"$@\"", "agentui"] + command }
        view.startProcess(executable: shell, args: args, environment: env.map { "\($0.key)=\($0.value)" }, currentDirectory: path)
        if !view.process.running {
            hasExited = true
            view.feed(text: String(localized: "Couldn’t start the terminal.") + "\r\n")
        }
    }

    func terminalReceived(_ slice: ArraySlice<UInt8>) {
        mirrorModes.append(slice)
        outputRevision += 1
        scheduleTranscriptRefresh()
    }

    func terminalUsedLocally() {
        takeBackGrid()
    }

    func takeBackGrid() {
        owner?.takeBackGrid(of: terminalID)
    }

    func acquireChat() {
        chatViewers += 1
        chatRelease?.cancel()
        chatRelease = nil
        journalMonitor.attach(agent?.journal)
        scheduleTranscriptRefresh()
    }

    func releaseChat() {
        chatViewers = max(0, chatViewers - 1)
        guard chatViewers == 0 else { return }
        chatRelease = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, chatViewers == 0 else { return }
            chatRelease = nil
            journalMonitor.suspend()
        }
    }

    private func scheduleTranscriptRefresh() {
        guard chatViewers > 0, transcript.source == .terminal, transcriptRefresh == nil else { return }
        transcriptRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            transcriptRefresh = nil
            updateTranscript()
        }
    }

    private func updateTranscript() {
        guard transcript.source == .terminal, (transcriptRevision != outputRevision || transcript.messages.isEmpty) else { return }
        transcriptRevision = outputRevision
        transcript.update(screen: view.getTerminal().recentText(limit: 65_536))
    }

    func send(_ data: Data, message: String? = nil, from origin: InputOrigin) async throws {
        guard data.count <= 65_536 else { throw WorkspaceError(message: String(localized: "Message too long (64 KB maximum).")) }
        let previous = pendingWrite
        let next = Task {
            _ = await previous?.result
            try await write(data, message: message, from: origin)
        }
        pendingWrite = next
        try await next.value
    }

    func launch(_ agent: ConversationAgent, skippingPermissions: Bool, from origin: InputOrigin) async throws {
        guard self.agent == nil, !isLaunchingAgent, isShellInForeground else {
            throw WorkspaceError(message: String(localized: "The terminal isn’t at the shell prompt. Finish the current command before launching an agent."))
        }
        isLaunchingAgent = true
        defer { isLaunchingAgent = false }
        let command = agent.launchCommand(skippingPermissions: skippingPermissions).joined(separator: " ")
        try await send(Data(("\u{15}" + command + "\r").utf8), from: origin)
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

    private func write(_ data: Data, message: String?, from origin: InputOrigin) async throws {
        guard !hasExited else { throw WorkspaceError(message: String(localized: "This session has ended.")) }
        guard let message else {
            deliver(Array(data)[...], from: origin)
            return
        }
        guard !isShellInForeground else { throw WorkspaceError(message: String(localized: "The agent stopped: the message wasn’t sent to the shell.")) }
        updateTranscript()
        let sentID = transcript.sent(message)
        guard data.last == 13, view.getTerminal().bracketedPasteMode else {
            deliver(Array(data)[...], from: origin)
            return
        }
        do { try await submitAsSinglePaste(data.dropLast(), from: origin) } catch {
            if let sentID { transcript.withdraw(sentID) }
            throw error
        }
    }

    private func submitAsSinglePaste(_ text: Data, from origin: InputOrigin) async throws {
        var paste = Data("\u{1b}[200~".utf8)
        paste.append(text)
        paste.append(Data("\u{1b}[201~".utf8))
        deliver(Array(paste)[...], from: origin)
        try await Task.sleep(for: .milliseconds(50))
        guard !hasExited else { throw WorkspaceError(message: String(localized: "This session has ended.")) }
        deliver([13][...], from: origin)
    }

    private func deliver(_ bytes: ArraySlice<UInt8>, from origin: InputOrigin) {
        switch origin {
        case .local: view.send(source: view, data: bytes)
        case .remote: view.sendRemoteInput(bytes)
        }
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
        let output = chat ? Data() : (screen ?? self.screen()).output(after: previousScreen)
        let messages = chat ? transcript.messages : []
        let delta = SessionTranscriptDelta(previous: previousMessages, current: messages)
        let terminal = view.getTerminal()
        return RemoteTerminalSnapshot(identity: identity, isChat: chat, output: output,
                                      columns: terminal.cols, rows: terminal.rows,
                                      transcript: delta.messages, transcriptDropped: delta.dropped, transcriptStart: delta.start,
                                      transcriptAppend: delta.append,
                                      hasExited: hasExited, exitCode: exitCode, chatSource: transcript.source)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        outputRevision += 1
        scheduleTranscriptRefresh()
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { self.title = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasExited = true
        agent = nil
        agentKind = nil
        agentStatus = nil
        subagents = []
        journalMonitor.attach(nil)
        self.exitCode = exitCode.flatMap { $0 & 0x7f == 0 ? ($0 >> 8) & 0xff : nil }
        owner?.agentStopped(in: terminalID)
    }
    func updateRepository(directory: String, branch: GitBranch?, divergentBranch: GitBranch?) {
        if currentDirectory != directory { currentDirectory = directory }
        if self.branch != branch { self.branch = branch }
        if self.divergentBranch != divergentBranch { self.divergentBranch = divergentBranch }
    }

    func updateAgent(_ process: AgentProcess?, subagents: [Subagent]) -> Bool {
        let running = hasExited ? nil : process?.keepingTranscript(of: agent)
        let children = running == nil ? [] : subagents
        let status = running.map { process in
            process.claudeStatus.flatMap(AgentStatus.init(claudeStatus:))
                ?? AgentStatus(screen: view.visibleLines, lastOutput: view.lastOutput)
        }
        if running != nil { hadAgent = true }
        let agentChanged = agent != running
        if agentChanged { agent = running }
        if agentKind != running?.agent { agentKind = running?.agent }
        if agentStatus != status { agentStatus = status }
        if self.subagents != children { self.subagents = children }
        if chatViewers > 0 || chatRelease != nil { journalMonitor.attach(running?.journal) }
        if agentChanged { scheduleTranscriptRefresh() }
        return owner?.recordAgent(agentKind, status: agentStatus, of: terminalID) ?? false
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
    private(set) var runningAgents: [UUID: ConversationAgent] = [:]
    private(set) var agentStatuses: [UUID: AgentStatus] = [:]
    @ObservationIgnored weak var delegate: TerminalSessionsDelegate?
    @ObservationIgnored private var refreshingRepositories = false
    @ObservationIgnored private var refreshingAgents = false
    @ObservationIgnored private var agentWatchers = 0
    @ObservationIgnored private var agentPolling: Task<Void, Never>?
    @ObservationIgnored private let subagentCatalog = ClaudeSubagents()
    @ObservationIgnored private var remoteGrids: [UUID: RemoteGridRequests] = [:]

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
                     fallback: session.currentDirectory, worktreePath: session.path)
        }
        let result = await Self.inspect(worktreePaths: worktreePaths, locations: locations)
        guard !Task.isCancelled else { return }
        if branchesByPath != result.branches { branchesByPath = result.branches }
        for value in result.sessions {
            guard let session = entries[value.id], session.identity == value.identity else { continue }
            session.updateRepository(directory: value.directory, branch: value.branch, divergentBranch: value.divergentBranch)
        }
    }

    private struct Location: Sendable {
        let id: UUID
        let identity: UUID
        let pid: Int32
        let fallback: String
        let worktreePath: String
    }

    private struct SessionRepository: Sendable {
        let id: UUID
        let identity: UUID
        let directory: String
        let branch: GitBranch?
        let divergentBranch: GitBranch?
    }

    private struct Inspection: Sendable {
        let branches: [String: GitBranch]
        let sessions: [SessionRepository]
    }

    @concurrent nonisolated private static func inspect(worktreePaths: [String], locations: [Location]) async -> Inspection {
        var cache: [String: GitRepository?] = [:]
        func repository(at path: String) -> GitRepository? {
            if let cached = cache[path] { return cached }
            let value = GitRepository.containing(path)
            cache[path] = .some(value)
            return value
        }
        var branches: [String: GitBranch] = [:]
        for path in Set(worktreePaths) { branches[path] = repository(at: path)?.branch }
        let sessions = locations.map { location in
            let directory = TerminalProcessDirectory.read(pid: location.pid) ?? location.fallback
            let current = repository(at: directory)
            return SessionRepository(id: location.id, identity: location.identity, directory: directory, branch: current?.branch,
                                     divergentBranch: current?.divergentBranch(from: repository(at: location.worktreePath)))
        }
        return Inspection(branches: branches, sessions: sessions)
    }

    func watchAgents() async {
        agentWatchers += 1
        if agentWatchers == 1 {
            agentPolling = Task(priority: .utility) { [weak self] in await self?.pollAgents() }
        }
        await Task.waitUntilCancelled()
        agentWatchers -= 1
        guard agentWatchers == 0 else { return }
        agentPolling?.cancel()
        agentPolling = nil
    }

    private func pollAgents() async {
        while !Task.isCancelled {
            await refreshAgents()
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    func refreshAgents() async {
        guard !refreshingAgents else { return }
        refreshingAgents = true
        defer { refreshingAgents = false }
        let shells = entries.compactMap { id, session in
            session.hasExited ? nil : (id: id, identity: session.identity, pid: session.view.process.shellPid,
                                       directory: session.currentDirectory, previous: session.agent)
        }
        let catalog = subagentCatalog
        let found = await Task.detached(priority: .utility) {
            let now = Date.now
            var result: [UUID: (process: AgentProcess, subagents: [Subagent])] = [:]
            for shell in shells {
                guard let process = AgentProcess.find(under: shell.pid, fallbackDirectory: shell.directory, previous: shell.previous) else { continue }
                result[shell.identity] = (process, await catalog.list(of: process.keepingTranscript(of: shell.previous), now: now))
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        let changes = entries.values.map { session in
            let agent = found[session.identity]
            return session.updateAgent(agent?.process, subagents: agent?.subagents ?? [])
        }
        if changes.contains(true) { delegate?.terminalSessionsDidChangeAgents() }
        delegate?.terminalSessionsDidRefreshAgents()
    }

    fileprivate func recordAgent(_ agent: ConversationAgent?, status: AgentStatus?, of id: UUID) -> Bool {
        guard runningAgents[id] != agent || agentStatuses[id] != status else { return false }
        if runningAgents[id] != agent { runningAgents[id] = agent }
        if agentStatuses[id] != status { agentStatuses[id] = status }
        return true
    }

    fileprivate func agentStopped(in id: UUID) {
        if recordAgent(nil, status: nil, of: id) { delegate?.terminalSessionsDidChangeAgents() }
    }

    func agentResumes() -> [UUID: AgentResume?] {
        entries.reduce(into: [:]) { result, entry in
            let session = entry.value
            let resume: AgentResume?
            if let agent = session.agent {
                guard let found = agent.resume ?? session.resume.flatMap({ $0.agent == agent.agent ? $0 : nil }) else {
                    if session.resume != nil { result.updateValue(nil, forKey: entry.key) }
                    session.resume = nil
                    return
                }
                resume = found
            } else if session.hasExited || session.hadAgent {
                resume = nil
            } else { return }
            session.resume = resume
            result.updateValue(resume, forKey: entry.key)
        }
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
    var runningWorkspaceCount: Int { entries.values.filter { !$0.isFloating && !$0.hasExited }.count }

    func session(_ id: UUID) -> TerminalSession? { entries[id] }
    func subagent(_ id: UUID?) -> SubagentSelection? {
        guard let id else { return nil }
        return entries.lazy.compactMap { terminalID, session in
            session.subagents.first { $0.id == id }.map { SubagentSelection(terminalID: terminalID, subagent: $0) }
        }.first
    }
    func isRunning(_ id: UUID) -> Bool { entries[id]?.hasExited == false }
    @discardableResult func start(_ context: TerminalContext, command: [String] = []) -> TerminalSession {
        if let session = entries[context.terminal.id] { return session }
        let resume = command.isEmpty ? context.terminal.resume.flatMap { $0.command == nil ? nil : $0 } : nil
        let session = TerminalSession(context: context, command: resume?.command ?? command, keepsShell: resume != nil, environment: environment)
        session.resume = resume
        session.owner = self
        entries[session.terminalID] = session
        updateRemoteGrid(of: session.terminalID) { _ in }
        return session
    }
    func close(_ id: UUID) {
        guard let session = entries.removeValue(forKey: id) else { return }
        session.owner = nil
        session.stop()
        agentStopped(in: id)
    }
    func stopAll() {
        for session in entries.values {
            session.owner = nil
            session.stop()
        }
        entries.removeAll()
        remoteGrids.removeAll()
        guard !runningAgents.isEmpty || !agentStatuses.isEmpty else { return }
        runningAgents = [:]
        agentStatuses = [:]
        delegate?.terminalSessionsDidChangeAgents()
    }

    func takeBackGrid(of terminal: UUID) {
        updateRemoteGrid(of: terminal) { $0.takeBack() }
    }

    func requestGrid(_ size: TerminalGridSize, for terminal: UUID, viewer: UUID) {
        updateRemoteGrid(of: terminal) { $0.request(size, by: viewer) }
    }

    func releaseGrid(of terminal: UUID, viewer: UUID) {
        updateRemoteGrid(of: terminal) { $0.withdraw(viewer) }
    }

    func receiveRemoteInput(_ data: Data, for terminal: UUID, viewer: UUID) {
        updateRemoteGrid(of: terminal) { $0.receive(data, from: viewer) }
    }

    private func updateRemoteGrid(of terminal: UUID, _ change: (inout RemoteGridRequests) -> Void) {
        var grids = remoteGrids[terminal] ?? RemoteGridRequests()
        change(&grids)
        remoteGrids[terminal] = grids.isEmpty ? nil : grids
        guard let session = entries[terminal], session.remoteGrid != grids.size else { return }
        session.remoteGrid = grids.size
    }
}

private extension AgentProcess {
    var journal: AgentJournal? {
        guard let source = SessionChatSource(agent: agent), let transcriptPath else { return nil }
        return AgentJournal(source: source, url: URL(fileURLWithPath: transcriptPath))
    }
}
