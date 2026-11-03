import Foundation
import Network
import Observation

@MainActor @Observable final class MobileWorkspaceStore {
    enum Status: Equatable { case disconnected, connecting, connected, failed(String) }

    private struct InterruptedInput: LocalizedError {
        var errorDescription: String? { String(localized: "Connection interrupted. Check the session before sending again.") }
    }

    private struct QueuedInput {
        let data: Data
        let terminal: UUID
        let message: String?
        let completion: (Error?) -> Void
    }

    private(set) var savedHosts: [SavedHost] {
        didSet { MobileSavedHosts.save(savedHosts, selection: selectedHostID) }
    }
    private(set) var selectedHostID: UUID? {
        didSet { MobileSavedHosts.save(savedHosts, selection: selectedHostID) }
    }
    private(set) var host: String
    private(set) var pairingCode: String
    private(set) var status: Status = .disconnected
    private(set) var workspace = Workspace()
    private(set) var session: MobileTerminalSession?
    private(set) var connectionID = UUID()
    private(set) var repositoryRevision = 0
    private(set) var conversationRevision = 0
    private(set) var installedAgents: [ConversationAgent] = []
    private(set) var terminalAgents: [UUID: ConversationAgent] = [:]
    var selection: UUID? {
        didSet { if selection != oldValue { session = nil } }
    }
    var wantsConnection = false
    var error: String?
    @ObservationIgnored private let pairingStores: @Sendable (String) -> any PairingCodeStore
    @ObservationIgnored private var pairingKey: PairingKey?
    @ObservationIgnored private var pairingDerivation: (code: String, task: Task<PairingKey?, Never>)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var streamConnection: NWConnection?
    @ObservationIgnored private var streamTerminal: UUID?
    @ObservationIgnored private var pendingInputs: [UUID: (Error?) -> Void] = [:]
    @ObservationIgnored private var inputTimeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var queuedInputs: [QueuedInput] = []
    @ObservationIgnored private var streamReady = false

    init(pairingStores: @escaping @Sendable (String) -> any PairingCodeStore = PairingCodeStores.make(account:)) {
        self.pairingStores = pairingStores
        let saved = MobileSavedHosts.load()
        let selected = saved.hosts.first { $0.id == saved.selection }
        savedHosts = saved.hosts
        selectedHostID = selected?.id
        host = selected?.addresses.first ?? ""
        var loadFailure: String?
        do { pairingCode = try selected.flatMap { try pairingStores($0.pairingAccount).load() } ?? "" } catch {
            pairingCode = ""
            loadFailure = error.localizedDescription
        }
        wantsConnection = !host.isEmpty && !pairingCode.isEmpty
        error = loadFailure
    }

    var isConnected: Bool { status == .connected }
    var selectedHost: SavedHost? { savedHosts.first { $0.id == selectedHostID } }
    var context: TerminalContext? { TerminalContext(terminalID: selection, in: workspace.projects) }
    var statusText: String {
        switch status {
        case .disconnected: String(localized: "Disconnected")
        case .connecting: String(localized: "Connecting to the Mac…")
        case .connected: String(localized: "Connected to \(selectedHost?.name ?? host)")
        case .failed(let message): message
        }
    }

    func connect(to address: String, pairingCode code: String) throws {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try RemoteProtocol.host(value)
        _ = try RemotePairing.normalized(code)
        let known = savedHosts.first { $0.addresses.contains(value) }
        let saved = (known ?? SavedHost(name: value, addresses: [value])).preferring(value)
        try pairingStores(saved.pairingAccount).save(code)
        remember(saved, replacing: [known].compactMap(\.self))
        open(saved, pairingCode: code)
    }

    func pair(with invitation: PairingInvitation) throws {
        let matches = savedHosts.filter { $0.id == invitation.hostID || !Set($0.addresses).isDisjoint(with: invitation.addresses) }
        let known = matches.first { $0.id == invitation.hostID } ?? matches.first
        var saved = SavedHost(id: invitation.hostID, name: invitation.name, addresses: invitation.addresses,
                              pairingAccount: known?.pairingAccount)
        if let working = known?.addresses.first, saved.addresses.contains(working) { saved = saved.preferring(working) }
        try pairingStores(saved.pairingAccount).save(invitation.code)
        for duplicate in matches where duplicate.pairingAccount != saved.pairingAccount {
            try? pairingStores(duplicate.pairingAccount).delete()
        }
        remember(saved, replacing: matches)
        open(saved, pairingCode: invitation.code)
    }

    func select(_ saved: SavedHost) throws {
        guard saved.id != selectedHostID || !wantsConnection else { return }
        guard let code = try pairingStores(saved.pairingAccount).load(), !code.isEmpty else {
            throw RemoteError(message: String(localized: "This Mac’s pairing code is missing. Scan its QR code again."))
        }
        open(saved, pairingCode: code)
    }

    func forget(_ saved: SavedHost) throws {
        try pairingStores(saved.pairingAccount).delete()
        if saved.id == selectedHostID {
            disconnect()
            selectedHostID = nil
            host = ""
            pairingCode = ""
            pairingKey = nil
            pairingDerivation = nil
            resetWorkspace()
        }
        savedHosts.removeAll { $0.id == saved.id }
    }

    private func remember(_ saved: SavedHost, replacing known: [SavedHost]) {
        var hosts = savedHosts
        let replaced = Set([saved.id] + known.map(\.id))
        let index = hosts.firstIndex { replaced.contains($0.id) } ?? hosts.endIndex
        hosts.removeAll { replaced.contains($0.id) }
        hosts.insert(saved, at: min(index, hosts.endIndex))
        savedHosts = hosts
    }

    private func open(_ saved: SavedHost, pairingCode code: String) {
        stopStream()
        if saved.id != selectedHostID { resetWorkspace() }
        selectedHostID = saved.id
        host = saved.addresses.first ?? ""
        pairingCode = code
        pairingKey = nil
        pairingDerivation = nil
        status = .connecting
        connectionID = UUID()
        wantsConnection = true
    }

    private func resetWorkspace() {
        workspace = Workspace()
        installedAgents = []
        terminalAgents = [:]
        selection = nil
    }

    private func tryNextAddress() {
        guard let addresses = selectedHost?.addresses, addresses.count > 1,
              let index = addresses.firstIndex(of: host) else { return }
        host = addresses[(index + 1) % addresses.count]
    }

    private func rememberWorkingAddress() {
        guard let saved = selectedHost, saved.addresses.first != host, saved.addresses.contains(host) else { return }
        remember(saved.preferring(host), replacing: [])
    }

    func disconnect() {
        wantsConnection = false
        stopStream()
        status = .disconnected
    }

    private func stopStream() {
        generation = UUID()
        streamConnection?.cancel()
        streamConnection = nil
        streamTerminal = nil
        cancelInputs(keepingQueuedFor: nil)
        terminalAgents = [:]
    }

    func watch(prefersChat: Bool) async {
        guard wantsConnection else { return }
        let selectedID = selection
        cancelInputs(keepingQueuedFor: selectedID)
        if session?.isChat == true, !prefersChat { session = nil }
        let token = UUID()
        generation = token
        streamReady = false
        let resumesStream = status == .connected
        if status != .connected { status = .connecting }
        do {
            let key = try await requiredPairingKey()
            guard generation == token else { return }
            let connection = try RemoteChannel.connection(to: host, key: key)
            streamConnection = connection
            streamTerminal = selectedID
            defer {
                connection.cancel()
                if generation == token {
                    streamConnection = nil
                    streamTerminal = nil
                    cancelInputs(keepingQueuedFor: selection == selectedID ? nil : selection)
                }
            }
            try await withTaskCancellationHandler {
                let request = RemoteRequest.watch(version: RemoteProtocol.version, terminal: selectedID, prefersChat: prefersChat)
                var first = true
                while !Task.isCancelled {
                    let event: RemoteEvent = try await (first ? RemoteChannel.firstEvent(after: request, on: connection) : RemoteChannel.receive(on: connection))
                    first = false
                    guard generation == token, !Task.isCancelled else { return }
                    if case .failure(let message) = event { throw RemoteError(message: message, isPermanent: true) }
                    if status != .connected {
                        status = .connected
                        rememberWorkingAddress()
                    }
                    if !streamReady {
                        streamReady = true
                        if resumesStream {
                            repositoryRevision += 1
                            conversationRevision += 1
                        }
                        if selection == selectedID { session?.resendGrid() }
                        sendQueuedInputs()
                    }
                    switch event {
                    case .workspace(let value):
                        if workspace != value { workspace = value }
                        if selectedID != nil, selection == selectedID, context == nil { selection = nil; session = nil }
                    case .terminal(let snapshot):
                        guard selection == selectedID else { continue }
                        if session?.identity != snapshot.identity || session?.isChat != snapshot.isChat {
                            session = MobileTerminalSession(identity: snapshot.identity, isChat: snapshot.isChat) { [weak self] data in
                                guard let self, let selectedID, self.isConnected else { return }
                                self.enqueueInput(data, terminal: selectedID, message: nil) { error in
                                    if let error, !(error is InterruptedInput), self.error == nil { self.error = error.localizedDescription }
                                }
                            } requestGrid: { [weak self] grid in
                                guard let self, let selectedID else { return }
                                self.requestGrid(grid, terminal: selectedID)
                            }
                        }
                        if session?.apply(snapshot) == false {
                            session = nil
                            connectionID = UUID()
                            return
                        }
                    case .terminalClosed:
                        if selection == selectedID { selection = nil }
                        return
                    case .failure: break
                    case .inputResult(let request, let error):
                        inputTimeouts.removeValue(forKey: request)?.cancel()
                        pendingInputs.removeValue(forKey: request)?(error.map { RemoteError(message: $0) })
                    case .repositoryChanged: repositoryRevision += 1
                    case .conversationsChanged: conversationRevision += 1
                    case .installedAgents(let agents): installedAgents = agents
                    case .terminalAgents(let agents): if terminalAgents != agents { terminalAgents = agents }
                    }
                }
            } onCancel: { connection.cancel() }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            status = .failed(error.localizedDescription)
            terminalAgents = [:]
            guard (error as? RemoteError)?.isPermanent != true else { wantsConnection = false; return }
            if !streamReady { tryNextAddress() }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if generation == token, wantsConnection { connectionID = UUID() }
        }
    }

    func suspend() {
        status = .disconnected
    }

    func input(_ data: Data, terminal: UUID, message: String? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            enqueueInput(data, terminal: terminal, message: message) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func enqueueInput(_ data: Data, terminal: UUID, message: String?, completion: @escaping (Error?) -> Void) {
        guard isConnected, selection == terminal else {
            completion(RemoteError(message: String(localized: "Reconnect to the Mac before sending.")))
            return
        }
        guard streamReady, streamTerminal == terminal, let connection = streamConnection else {
            queuedInputs.append(QueuedInput(data: data, terminal: terminal, message: message, completion: completion))
            return
        }
        let id = UUID()
        pendingInputs[id] = completion
        do {
            try RemoteChannel.enqueue(RemoteRequest.streamInput(request: id, terminal: terminal, data: data, message: message), on: connection) { [weak self] error in
                Task { @MainActor in self?.finishInput(id, error: error) }
            }
        } catch {
            finishInput(id, error: error)
            return
        }
        inputTimeouts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, pendingInputs[id] != nil else { return }
            finishInput(id, error: RemoteError(message: String(localized: "Sending not confirmed. Check the session before sending again.")))
            connection.cancel()
        }
    }

    private func requestGrid(_ grid: TerminalGridSize, terminal: UUID) {
        guard streamReady, streamTerminal == terminal, let connection = streamConnection else { return }
        try? RemoteChannel.enqueue(RemoteRequest.resizeTerminal(terminal: terminal, size: grid), on: connection) { _ in }
    }

    private func sendQueuedInputs() {
        let queued = queuedInputs
        queuedInputs.removeAll()
        for input in queued {
            enqueueInput(input.data, terminal: input.terminal, message: input.message, completion: input.completion)
        }
    }

    private func finishInput(_ id: UUID, error: Error?) {
        inputTimeouts.removeValue(forKey: id)?.cancel()
        pendingInputs.removeValue(forKey: id)?(error)
    }

    func requiredPairingKey() async throws -> PairingKey {
        if let pairingKey { return pairingKey }
        let code = pairingCode
        let derivation: Task<PairingKey?, Never>
        if let pending = pairingDerivation, pending.code == code {
            derivation = pending.task
        } else {
            derivation = Task { try? await PairingKey.derive(from: code) }
            pairingDerivation = (code, derivation)
        }
        let key = await derivation.value
        if pairingDerivation?.code == code { pairingDerivation = nil }
        guard let key else {
            throw RemoteError(message: String(localized: "Enter the pairing code shown on the Mac in Settings → Local Access."), isPermanent: true)
        }
        if pairingCode == code { pairingKey = key }
        return key
    }

    private func cancelInputs(keepingQueuedFor terminal: UUID?) {
        for timeout in inputTimeouts.values { timeout.cancel() }
        inputTimeouts.removeAll()
        let dropped = queuedInputs.filter { terminal == nil || $0.terminal != terminal }
        let pending = Array(pendingInputs.values) + dropped.map(\.completion)
        pendingInputs.removeAll()
        queuedInputs.removeAll { terminal == nil || $0.terminal != terminal }
        for completion in pending {
            completion(InterruptedInput())
        }
    }

    func launch(_ agent: ConversationAgent, in context: TerminalContext) async {
        do {
            let _: Bool = try await RemoteChannel.call(.launchAgent(terminal: context.terminal.id, agent: agent),
                                                       host: host, key: try await requiredPairingKey())
        } catch { self.error = error.localizedDescription }
    }

    func newTerminal(in context: TerminalContext) async {
        do {
            let id: UUID = try await RemoteChannel.call(.newTerminal(project: context.project.id, worktree: context.worktree.id),
                                                        host: host, key: try await requiredPairingKey())
            selection = id
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor struct MobileInspectorSource: InspectorSource {
    let host: String
    let terminal: UUID
    let store: MobileWorkspaceStore

    private func request<Value: Decodable & Sendable>(_ request: RemoteRequest) async throws -> Value {
        guard store.wantsConnection, store.host == host else { throw RemoteError(message: String(localized: "The Mac is disconnected.")) }
        return try await RemoteChannel.call(request, host: host, key: try await store.requiredPairingKey())
    }

    func children(at url: URL) async throws -> ExplorerListing {
        try await request(.children(terminal: terminal, path: url.path))
    }
    func textFile(_ url: URL) async throws -> String {
        try await request(.text(terminal: terminal, path: url.path))
    }
    func localGit(at path: String) async throws -> LocalGitSnapshot {
        try await request(.git(terminal: terminal))
    }
    func remote(_ snapshot: LocalGitSnapshot) async throws -> RemoteSnapshot {
        try await request(.github(terminal: terminal))
    }
    func diff(_ change: GitChange, in scope: GitChangeScope, at root: String) async throws -> GitDiff {
        let value: RemoteDiff = switch scope {
        case .staged: try await request(.diff(terminal: terminal, change: change, including: [.staged]))
        case .unstaged: try await request(.diff(terminal: terminal, change: change, including: [.unstaged]))
        case .branch(let base): try await request(.comparisonDiff(terminal: terminal, base: base, change: change))
        }
        return value.diff
    }
    func branches(at root: String) async throws -> GitBranchList {
        try await request(.branches(terminal: terminal))
    }
    func comparison(with base: ComparisonBranch, at root: String) async throws -> BranchComparison {
        try await request(.comparison(terminal: terminal, base: base))
    }
    func conversations(at path: String, fresh: Bool) async throws -> [AgentConversation] {
        try await request(.conversations(terminal: terminal, fresh: fresh))
    }
    func resume(_ conversation: AgentConversation, context: TerminalContext) async throws {
        let id: UUID = try await request(.resume(terminal: terminal, conversation: conversation))
        store.selection = id
    }
    func repositoryChanges(at path: String) async -> AsyncStream<Void> {
        changes { [store] in (store.repositoryRevision, store.isConnected) }
    }
    func conversationChanges() async -> AsyncStream<Void> {
        changes { [store] in (store.conversationRevision, store.isConnected) }
    }

    private func changes(_ revision: @escaping @MainActor () -> (Int, Bool)) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                var last: (Int, Bool)?
                while !Task.isCancelled {
                    let (changed, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
                    let value = withObservationTracking(revision) { signal.yield() }
                    if value.1, last.map({ $0 != value }) ?? true { continuation.yield() }
                    last = value
                    for await _ in changed { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
