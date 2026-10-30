import Foundation
import Network
import Observation

@MainActor @Observable final class MobileWorkspaceStore {
    enum Status: Equatable { case disconnected, connecting, connected, failed(String) }
    private(set) var host = UserDefaults.standard.string(forKey: "remoteHost") ?? ""
    private(set) var pairingCode: String
    private(set) var status: Status = .disconnected
    private(set) var workspace = Workspace()
    private(set) var session: MobileTerminalSession?
    private(set) var connectionID = UUID()
    private(set) var repositoryRevision = 0
    private(set) var conversationRevision = 0
    private(set) var installedAgents: [ConversationAgent] = []
    var selection: UUID? {
        didSet { if selection != oldValue { session = nil } }
    }
    var wantsConnection = false
    var error: String?
    @ObservationIgnored private let pairingStore: any PairingCodeStore
    @ObservationIgnored private var pairingKey: PairingKey?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var streamConnection: NWConnection?
    @ObservationIgnored private var pendingInputs: [UUID: (Error?) -> Void] = [:]
    @ObservationIgnored private var inputTimeouts: [UUID: Task<Void, Never>] = [:]

    init(pairingStore: any PairingCodeStore = PairingCodeStores.make(account: "remotePairingCode")) {
        self.pairingStore = pairingStore
        pairingCode = (try? pairingStore.load()) ?? ""
        pairingKey = try? PairingKey(code: pairingCode)
        wantsConnection = !host.isEmpty && pairingKey != nil
    }

    var isConnected: Bool { status == .connected }
    var context: TerminalContext? { TerminalContext(terminalID: selection, in: workspace.projects) }
    var statusText: String {
        switch status {
        case .disconnected: "Déconnecté"
        case .connecting: "Connexion au Mac…"
        case .connected: "Connecté à \(host)"
        case .failed(let message): message
        }
    }

    func connect(to address: String, pairingCode code: String) throws {
        _ = try RemoteProtocol.host(address)
        let key = try PairingKey(code: code)
        try pairingStore.save(code)
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if host != value {
            workspace = Workspace()
            selection = nil
            session = nil
        }
        host = value
        pairingCode = code
        pairingKey = key
        UserDefaults.standard.set(host, forKey: "remoteHost")
        status = .connecting
        connectionID = UUID()
        wantsConnection = true
    }

    func disconnect() {
        wantsConnection = false
        generation = UUID()
        streamConnection?.cancel()
        streamConnection = nil
        cancelInputs()
        status = .disconnected
    }

    func watch(prefersChat: Bool) async {
        guard wantsConnection else { return }
        cancelInputs()
        if session?.isChat == true, !prefersChat { session = nil }
        let token = UUID()
        generation = token
        status = .connecting
        let selectedID = selection
        do {
            let connection = NWConnection(host: try RemoteProtocol.host(host), port: NWEndpoint.Port(rawValue: RemoteProtocol.port)!,
                                          using: RemoteChannel.parameters(key: try requiredPairingKey()))
            streamConnection = connection
            defer {
                connection.cancel()
                if generation == token {
                    streamConnection = nil
                    cancelInputs()
                }
            }
            try await withTaskCancellationHandler {
                let request = RemoteRequest.watch(version: RemoteProtocol.version, terminal: selectedID, prefersChat: prefersChat)
                var first = true
                while !Task.isCancelled {
                    let event: RemoteEvent = try await (first ? RemoteChannel.firstEvent(after: request, on: connection) : RemoteChannel.receive(on: connection))
                    first = false
                    guard generation == token, !Task.isCancelled else { return }
                    if status != .connected { status = .connected }
                    switch event {
                    case .workspace(let value):
                        if workspace != value { workspace = value }
                        if selectedID != nil, selection == selectedID, context == nil { selection = nil; session = nil }
                    case .terminal(let snapshot):
                        guard selection == selectedID else { continue }
                        if session?.identity != snapshot.identity || session?.isChat != snapshot.isChat {
                            session = MobileTerminalSession(identity: snapshot.identity, isChat: snapshot.isChat) { [weak self] data in
                                guard let self, let selectedID else { return }
                                self.enqueueInput(data, terminal: selectedID, message: nil) { error in
                                    if let error, self.error == nil { self.error = error.localizedDescription }
                                }
                            }
                        }
                        session?.apply(snapshot)
                    case .failure(let message):
                        if selectedID != nil, selection != selectedID { return }
                        throw RemoteError(message: message, isPermanent: true)
                    case .inputResult(let request, let error):
                        inputTimeouts.removeValue(forKey: request)?.cancel()
                        pendingInputs.removeValue(forKey: request)?(error.map { RemoteError(message: $0) })
                    case .repositoryChanged: repositoryRevision += 1
                    case .conversationsChanged: conversationRevision += 1
                    case .installedAgents(let agents): installedAgents = agents
                    }
                }
            } onCancel: { connection.cancel() }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            status = .failed(error.localizedDescription)
            guard (error as? RemoteError)?.isPermanent != true else { wantsConnection = false; return }
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
        guard isConnected, let connection = streamConnection, selection == terminal else {
            completion(RemoteError(message: "Reconnecte-toi au Mac avant d’envoyer."))
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
            finishInput(id, error: RemoteError(message: "Envoi non confirmé. Vérifie la session avant de renvoyer."))
            connection.cancel()
        }
    }

    private func finishInput(_ id: UUID, error: Error?) {
        inputTimeouts.removeValue(forKey: id)?.cancel()
        pendingInputs.removeValue(forKey: id)?(error)
    }

    func requiredPairingKey() throws -> PairingKey {
        guard let pairingKey else {
            throw RemoteError(message: "Saisis le code d’appairage affiché sur le Mac dans Réglages → Accès local.", isPermanent: true)
        }
        return pairingKey
    }

    private func cancelInputs() {
        for timeout in inputTimeouts.values { timeout.cancel() }
        inputTimeouts.removeAll()
        let pending = pendingInputs
        pendingInputs.removeAll()
        for completion in pending.values {
            completion(RemoteError(message: "Connexion interrompue. Vérifie la session avant de renvoyer."))
        }
    }

    func launch(_ agent: ConversationAgent, in context: TerminalContext) async {
        do {
            let _: Bool = try await RemoteChannel.call(.launchAgent(terminal: context.terminal.id, agent: agent),
                                                       host: host, key: try requiredPairingKey())
        } catch { self.error = error.localizedDescription }
    }

    func newTerminal(in context: TerminalContext) async {
        do {
            let id: UUID = try await RemoteChannel.call(.newTerminal(project: context.project.id, worktree: context.worktree.id),
                                                        host: host, key: try requiredPairingKey())
            selection = id
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor struct MobileInspectorSource: InspectorSource {
    let host: String
    let terminal: UUID
    let store: MobileWorkspaceStore

    private func request<Value: Decodable & Sendable>(_ request: RemoteRequest) async throws -> Value {
        guard store.wantsConnection, store.host == host else { throw RemoteError(message: "Le Mac est déconnecté.") }
        return try await RemoteChannel.call(request, host: host, key: try store.requiredPairingKey())
    }

    func children(at url: URL) async throws -> [ExplorerEntry] {
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
    func diff(_ change: GitChange, at root: String) async throws -> GitDiff {
        let value: RemoteDiff = try await request(.diff(terminal: terminal, change: change))
        return value.diff
    }
    func conversations(at path: String, fresh: Bool) async throws -> [AgentConversation] {
        try await request(.conversations(terminal: terminal))
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
