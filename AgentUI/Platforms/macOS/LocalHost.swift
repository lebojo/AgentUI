import Foundation
import Network
import Observation

@MainActor @Observable final class LocalHost {
    var enabled = UserDefaults.standard.bool(forKey: "localHost.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "localHost.enabled")
            restart()
        }
    }
    private(set) var pairingCode = ""
    private(set) var pairingStorageError: String?
    private(set) var status = "Accès local désactivé"
    private(set) var addresses: [String] = []
    @ObservationIgnored private let pairingStore: any PairingCodeStore
    @ObservationIgnored private var pairingKey: PairingKey?
    @ObservationIgnored private weak var store: WorkspaceStore?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var installedAgents: InstalledAgents?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var listenerRetry: Task<Void, Never>?
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var connections: [UUID: (connection: NWConnection, peer: String)] = [:]

    private static let maximumConnections = 32
    private static let maximumConnectionsPerPeer = 8

    init(pairingStore: any PairingCodeStore = PairingCodeStores.make(account: "localHost.pairingCode")) {
        self.pairingStore = pairingStore
    }

    func configure(store: WorkspaceStore, settings: SettingsStore, installedAgents: InstalledAgents) {
        guard self.store == nil else { return }
        self.store = store
        self.settings = settings
        self.installedAgents = installedAgents
        restart()
    }

    func renewPairingCode() {
        do {
            try storeNewPairingCode()
            restart()
        } catch { pairingStorageError = error.localizedDescription }
    }

    private func loadPairingKey() throws -> PairingKey {
        if let pairingKey { return pairingKey }
        if let code = try pairingStore.load(), let key = try? PairingKey(code: code) {
            pairingCode = code
            pairingKey = key
            return key
        }
        return try storeNewPairingCode()
    }

    @discardableResult private func storeNewPairingCode() throws -> PairingKey {
        let code = RemotePairing.newCode()
        let key = try PairingKey(code: code)
        try pairingStore.save(code)
        pairingCode = code
        pairingKey = key
        pairingStorageError = nil
        return key
    }

    func stop() {
        listenerRetry?.cancel()
        listenerRetry = nil
        listener?.cancel()
        listener = nil
        for job in jobs.values { job.cancel() }
        for entry in connections.values { entry.connection.cancel() }
        jobs.removeAll()
        connections.removeAll()
    }

    private func restart() {
        stop()
        guard enabled, store != nil else { status = "Accès local désactivé"; return }
        addresses = Self.localAddresses()
        do {
            let parameters = RemoteChannel.parameters(key: try loadPairingKey())
            #if DEBUG
            let isolatedFixtureListensOnLoopbackOnly = ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil
            if isolatedFixtureListensOnLoopbackOnly {
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: RemoteProtocol.port)!)
            }
            #endif
            let listener = try parameters.requiredLocalEndpoint == nil
                ? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: RemoteProtocol.port)!)
                : NWListener(using: parameters)
            self.listener = listener
            status = "Démarrage…"
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, self.listener === listener else { return }
                    switch state {
                    case .ready: self.status = "Prêt à recevoir une connexion"
                    case .failed(let error):
                        self.stop()
                        self.status = "\(error.localizedDescription) Nouvelle tentative dans 5 secondes…"
                        self.retryListener()
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.accept(connection) }
            }
            listener.start(queue: .main)
        } catch { status = error.localizedDescription }
    }

    private func retryListener() {
        listenerRetry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.restart()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, (try? RemoteProtocol.host(String(describing: host))) != nil,
              connections.count < Self.maximumConnections,
              connections.values.count(where: { $0.peer == String(describing: host) }) < Self.maximumConnectionsPerPeer else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = (connection, String(describing: host))
        connection.start(queue: .global(qos: .userInitiated))
        jobs[id] = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            defer {
                connection.cancel()
                self.connections[id] = nil
                self.jobs[id] = nil
            }
            do {
                let request = try await self.readRequest(connection)
                if case .watch(let version, let terminal, let prefersChat) = request {
                    try await self.watch(connection, version: version, terminal: terminal, prefersChat: prefersChat)
                } else {
                    let reply: RemoteReply
                    do { reply = try await self.handle(request) }
                    catch { reply = RemoteReply(error: error.localizedDescription) }
                    try await RemoteChannel.send(reply, on: connection)
                }
            } catch {}
        }
    }

    private func readRequest(_ connection: NWConnection) async throws -> RemoteRequest {
        try await RemoteChannel.withTimeout(on: connection, failure: CancellationError()) {
            try await RemoteChannel.receive(on: connection)
        }
    }

    private func watch(_ connection: NWConnection, version: Int, terminal: UUID?, prefersChat: Bool) async throws {
        guard version == RemoteProtocol.version, let store else {
            try await RemoteChannel.send(RemoteEvent.failure("Versions incompatibles. Mets les deux applications à jour."), on: connection)
            return
        }
        _ = terminal.flatMap { store.context(for: $0) }.map { store.sessions.start($0) }
        let notifications = Task { await notifyInspectorChanges(on: connection, terminal: terminal) }
        defer { notifications.cancel() }
        var sessionIdentity: UUID?
        var streamsChat: Bool?
        var previousAgents: [ConversationAgent]?
        var previousScreen: TerminalScreen?
        var previousWorkspace: Workspace?
        var watchedChat: TerminalSession?
        var previousSource: SessionChatSource?
        defer { watchedChat?.releaseChat() }
        var previousMessages: [SessionMessage] = []
        var previousRevision = -1
        var previousExit: Bool?
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: continuation.finish()
            default: break
            }
        }
        let inputTask = Task {
            defer { continuation.finish() }
            do {
                while !Task.isCancelled {
                    let request: RemoteRequest = try await RemoteChannel.receive(on: connection)
                    guard case .streamInput(let requestID, let terminalID, let data, let message) = request,
                          terminalID == terminal else { return }
                    let failure: String?
                    do {
                        _ = try await handle(.input(id: terminalID, data: data, message: message))
                        failure = nil
                    } catch { failure = error.localizedDescription }
                    try await RemoteChannel.send(RemoteEvent.inputResult(request: requestID, error: failure), on: connection)
                }
            } catch {}
        }
        continuation.yield(())
        defer { continuation.finish(); inputTask.cancel() }
        for await _ in changes {
            try Task.checkCancellation()
            withObservationTracking {
                _ = store.state
                let session = terminal.flatMap { store.sessions.session($0) }
                _ = session?.outputRevision
                _ = session?.hasExited
                _ = session?.transcript.messages
                _ = session?.transcript.source
                _ = session?.agent
                _ = installedAgents?.agents
            } onChange: { continuation.yield(()) }
            try await Task.sleep(for: .milliseconds(100))
            let workspace = store.state
            if previousWorkspace != workspace {
                try await RemoteChannel.send(RemoteEvent.workspace(workspace), on: connection)
                previousWorkspace = workspace
            }
            let agents = installedAgents?.agents ?? []
            if previousAgents != agents {
                try await RemoteChannel.send(RemoteEvent.installedAgents(agents), on: connection)
                previousAgents = agents
            }
            if let terminal, store.context(for: terminal) == nil {
                try await RemoteChannel.send(RemoteEvent.failure("Ce terminal a été fermé sur le Mac."), on: connection)
                return
            }
            let session = terminal.flatMap { store.sessions.session($0) }
            let chat = prefersChat && session?.agent != nil
            if sessionIdentity != session?.identity || streamsChat != chat {
                watchedChat?.releaseChat()
                watchedChat = chat ? session : nil
                watchedChat?.acquireChat()
                streamsChat = chat
                previousSource = nil
                sessionIdentity = session?.identity
                previousRevision = -1
                previousExit = nil
                previousMessages = []
                previousScreen = nil
                continuation.yield(())
            }
            if let session, previousRevision != session.outputRevision || previousExit != session.hasExited
                || (chat && (previousMessages != session.transcript.messages || previousSource != session.transcript.source)) {
                previousRevision = session.outputRevision
                if chat { session.updateTranscript() }
                let chatUnchanged = chat && previousExit == session.hasExited
                    && previousMessages == session.transcript.messages && previousSource == session.transcript.source
                guard !chatUnchanged else { continue }
                let screen = chat ? nil : session.screen()
                let snapshot = session.snapshot(previousMessages: previousMessages, chat: chat, screen: screen, previousScreen: previousScreen)
                let messages = session.transcript.messages
                let source = session.transcript.source
                try await RemoteChannel.send(RemoteEvent.terminal(snapshot), on: connection)
                previousScreen = screen
                previousExit = snapshot.hasExited
                if chat { previousMessages = messages; previousSource = source }
            }
        }
    }

    private func notifyInspectorChanges(on connection: NWConnection, terminal: UUID?) async {
        guard let path = terminal.flatMap({ store?.context(for: $0) })?.worktree.path else { return }
        let repository = await FileEvents.repositoryChanges(at: path)
        let conversations = FileEvents.changes(in: ConversationIndex.watchedDirectories, latency: .seconds(1), every: .seconds(15))
        await withTaskGroup { group in
            group.addTask {
                for await _ in repository.dropFirst() { try? await RemoteChannel.send(RemoteEvent.repositoryChanged, on: connection) }
            }
            group.addTask {
                for await _ in conversations.dropFirst() { try? await RemoteChannel.send(RemoteEvent.conversationsChanged, on: connection) }
            }
        }
    }

    private func handle(_ request: RemoteRequest) async throws -> RemoteReply {
        guard let store else { throw RemoteError(message: "Le Mac n’est pas prêt.") }
        switch request {
        case .watch, .streamInput: throw RemoteError(message: "Requête invalide.")
        case .workspace(let version):
            guard version == RemoteProtocol.version else { throw RemoteError(message: "Versions incompatibles.") }
            return try .success(store.state)
        case .terminal(let id, _):
            return try .success(store.sessions.start(try context(id)).snapshot(previousMessages: [], chat: true))
        case .input(let id, let data, let message):
            try requireWritable()
            guard data.count <= 65_536, (message?.utf8.count ?? 0) <= 65_536 else { throw RemoteError(message: "Message trop long.") }
            try await store.sessions.start(try context(id)).send(data, message: message)
            return try .success(true)
        case .newTerminal(let project, let worktree):
            try requireWritable()
            let launch = settings?.agentLaunch ?? AgentLaunch()
            let id = try store.addTerminal(projectID: project, worktreeID: worktree,
                                           command: launch.command(on: .newTerminal), select: false)
            return try .success(id.terminal.id)
        case .children(let id, let path):
            return try await .success(InspectorService.children(at: validatedURL(path, terminal: id)))
        case .text(let id, let path):
            return try await .success(InspectorService.textFile(validatedURL(path, terminal: id)))
        case .git(let id):
            return try await .success(InspectorService.localGit(at: context(id).worktree.path))
        case .github(let id):
            let local = try await InspectorService.localGit(at: context(id).worktree.path)
            return try await .success(InspectorService.remote(for: local))
        case .diff(let id, let change):
            let local = try await InspectorService.localGit(at: context(id).worktree.path)
            guard let actual = local.changes.first(where: { $0.path == change.path }) else { throw RemoteError(message: "Le fichier n’a plus de modifications.") }
            _ = try validatedURL(URL(fileURLWithPath: local.root).appendingPathComponent(actual.path).path, terminal: id)
            return try await .success(RemoteDiff(InspectorService.diff(actual, at: local.root)))
        case .conversations(let id):
            return try await .success(ConversationIndex.load(at: context(id).worktree.path))
        case .launchAgent(let id, let agent):
            try requireWritable()
            let session = store.sessions.start(try context(id))
            try await session.launch(agent, skippingPermissions: settings?.agentLaunch.skipsPermissions ?? false)
            return try .success(true)
        case .resume(let id, let conversation):
            try requireWritable()
            let context = try context(id)
            let available = await ConversationIndex.load(at: context.worktree.path, runningMaximumAge: .zero)
            guard let actual = available.first(where: { $0.id == conversation.id }), !actual.isRunning else {
                throw RemoteError(message: "Cette conversation n’est plus disponible ou est déjà ouverte.")
            }
            let resumed = try store.resume(actual, projectID: context.project.id, worktreeID: context.worktree.id, select: false)
            return try .success(resumed.terminal.id)
        }
    }

    private func requireWritable() throws {
        guard store?.isReadOnly != true else { throw RemoteError(message: "L’organisation du Mac est en lecture seule.") }
    }

    private func context(_ id: UUID) throws -> TerminalContext {
        guard let context = store?.context(for: id) else { throw RemoteError(message: "Ce terminal n’existe plus sur le Mac.") }
        return context
    }

    private func validatedURL(_ path: String, terminal: UUID) throws -> URL {
        let root = URL(fileURLWithPath: try context(terminal).worktree.path).resolvingSymlinksInPath()
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw RemoteError(message: "Le fichier est en dehors de ce worktree.")
        }
        return url
    }

    private static func localAddresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        var addresses: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: buffer)
                if (try? RemoteProtocol.host(value)) != nil { addresses.append(value) }
            }
        }
        return Array(Set(addresses)).sorted()
    }
}
