import Foundation
import Network
import Observation

@MainActor @Observable final class LocalHost {
    private struct StreamedSession {
        var identity: UUID?
        var chat: Bool?
        var screen: TerminalScreen?
        var messages: [SessionMessage] = []
        var source: SessionChatSource?
        var revision = -1
        var hasExited: Bool?
    }

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
    @ObservationIgnored private var pairingUpdate: Task<PairingKey, Error>?
    @ObservationIgnored private weak var store: WorkspaceStore?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var installedAgents: InstalledAgents?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var listenerStart: Task<Void, Never>?
    @ObservationIgnored private var listenerRetry: Task<Void, Never>?
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var connections: [UUID: (connection: NWConnection, peer: String, isPaired: Bool)] = [:]
    @ObservationIgnored private let pathMonitor = NWPathMonitor()

    private static let maximumConnections = 32
    private static let maximumUnpairedConnections = 64
    private static let maximumConnectionsPerPeer = 16
    private static let incompatibleVersions = "Versions incompatibles. Mets à jour AgentUI sur le Mac et sur cet appareil."

    init(pairingStore: any PairingCodeStore = PairingCodeStores.make(account: "localHost.pairingCode")) {
        self.pairingStore = pairingStore
    }

    func configure(store: WorkspaceStore, settings: SettingsStore, installedAgents: InstalledAgents) {
        guard self.store == nil else { return }
        self.store = store
        self.settings = settings
        self.installedAgents = installedAgents
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAddresses() }
        }
        pathMonitor.start(queue: .main)
        restart()
    }

    private func refreshAddresses() {
        guard enabled, store != nil else { return }
        let current = Self.localAddresses()
        if addresses != current { addresses = current }
    }

    func renewPairingCode() {
        Task {
            do {
                try await storeNewPairingCode()
                restart()
            } catch { pairingStorageError = error.localizedDescription }
        }
    }

    private func loadPairingKey() async throws -> PairingKey {
        if let pairingKey { return pairingKey }
        let codes = pairingStore
        let stored: String?
        do { stored = try await Task.detached(operation: { try codes.load() }).value }
        catch { throw storageFailure(error.localizedDescription) }
        guard let code = stored else {
            do {
                if let pairingUpdate { return try await pairingUpdate.value }
                return try await storeNewPairingCode()
            }
            catch { throw storageFailure(error.localizedDescription) }
        }
        guard let key = try? await PairingKey.derive(from: code) else {
            throw storageFailure("Le code d’appairage enregistré est illisible. Génère un nouveau code pour appairer à nouveau tes appareils.")
        }
        if let pairingKey { return pairingKey }
        pairingCode = code
        pairingKey = key
        pairingStorageError = nil
        return key
    }

    private func storageFailure(_ message: String) -> RemoteError {
        pairingStorageError = message
        return RemoteError(message: message, isPermanent: true)
    }

    @discardableResult private func storeNewPairingCode() async throws -> PairingKey {
        let previous = pairingUpdate
        let codes = pairingStore
        let update = Task { [weak self] in
            _ = await previous?.result
            let code = RemotePairing.newCode()
            let key = try await PairingKey.derive(from: code)
            try await Task.detached { try codes.save(code) }.value
            self?.pairingCode = code
            self?.pairingKey = key
            self?.pairingStorageError = nil
            return key
        }
        pairingUpdate = update
        defer { if pairingUpdate == update { pairingUpdate = nil } }
        return try await update.value
    }

    func stop() {
        listenerStart?.cancel()
        listenerStart = nil
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
        status = "Démarrage…"
        listenerStart = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try await loadPairingKey()
                guard !Task.isCancelled else { return }
                try listen(with: key)
            } catch {
                guard !Task.isCancelled else { return }
                guard (error as? RemoteError)?.isPermanent != true else { status = error.localizedDescription; return }
                status = "\(error.localizedDescription) Nouvelle tentative dans 5 secondes…"
                retryListener()
            }
        }
    }

    private func listen(with key: PairingKey) throws {
        let parameters = RemoteChannel.parameters(key: key)
        parameters.allowLocalEndpointReuse = true
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
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor [weak self, weak listener] in
                guard let self, let listener, self.listener === listener, self.enabled else {
                    connection.cancel()
                    return
                }
                self.accept(connection)
            }
        }
        listener.start(queue: .main)
    }

    private func retryListener() {
        listenerRetry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.restart()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, (try? RemoteProtocol.host(String(describing: host))) != nil,
              connections.values.count(where: \.isPaired) < Self.maximumConnections,
              connections.values.count(where: { !$0.isPaired }) < Self.maximumUnpairedConnections,
              connections.values.count(where: { $0.peer == String(describing: host) }) < Self.maximumConnectionsPerPeer else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = (connection, String(describing: host), false)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in self?.connections[id]?.isPaired = true }
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.connections[id] = nil
                    self?.jobs[id]?.cancel()
                }
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        jobs[id] = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            defer {
                connection.cancel()
                self.connections[id] = nil
                self.jobs[id] = nil
            }
            do {
                let request: RemoteRequest
                do { request = try await self.readRequest(connection) }
                catch is DecodingError {
                    try await RemoteChannel.send(RemoteRejection(Self.incompatibleVersions), on: connection)
                    return
                }
                if case .watch(let version, let terminal, let prefersChat) = request {
                    try await self.watch(connection, version: version, terminal: terminal, prefersChat: prefersChat)
                } else {
                    RemoteChannel.cancelWhenPeerCloses(connection)
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
        guard let store else { return }
        guard version == RemoteProtocol.version else {
            try await RemoteChannel.send(RemoteEvent.failure(Self.incompatibleVersions), on: connection)
            return
        }
        Task { await installedAgents?.refresh() }
        let agentWatch = terminal == nil ? nil : Task { await store.sessions.watchAgents() }
        defer { agentWatch?.cancel() }
        let notifications = Task { await notifyInspectorChanges(on: connection, terminal: terminal) }
        defer { notifications.cancel() }
        var previousAgents: [ConversationAgent]?
        var previousWorkspace: Workspace?
        var streamed = StreamedSession()
        var watchedChat: TerminalSession?
        defer { watchedChat?.releaseChat() }
        let streamsChat = { (session: TerminalSession?) in prefersChat && session?.agent != nil }
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
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
                _ = store.folders
                _ = store.projects
                let session = terminal.flatMap { store.sessions.session($0) }
                if session == nil { _ = terminal.flatMap { store.startableContext(for: $0) } }
                if streamsChat(session) {
                    _ = session?.transcript.messages
                    _ = session?.transcript.source
                } else {
                    _ = session?.outputRevision
                }
                _ = session?.hasExited
                _ = session?.agent
                _ = installedAgents?.agents
            } onChange: { continuation.yield(()) }
            try await Task.sleep(for: .milliseconds(100))
            let workspace = Workspace(folders: store.folders, projects: store.projects, selection: nil, collapsed: [])
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
                try await RemoteChannel.send(RemoteEvent.terminalClosed, on: connection)
                return
            }
            if let terminal, store.sessions.session(terminal) == nil { store.startSession(for: terminal) }
            let session = terminal.flatMap { store.sessions.session($0) }
            let chat = streamsChat(session)
            if streamed.identity != session?.identity || streamed.chat != chat {
                watchedChat?.releaseChat()
                watchedChat = chat ? session : nil
                watchedChat?.acquireChat()
                streamed = StreamedSession(identity: session?.identity, chat: chat)
                continuation.yield(())
            }
            guard let session else { continue }
            let exitChanged = streamed.hasExited != session.hasExited
            let changed = chat
                ? exitChanged || streamed.messages != session.transcript.messages || streamed.source != session.transcript.source
                : exitChanged || streamed.revision != session.outputRevision
            streamed.revision = session.outputRevision
            if changed {
                let screen = chat ? nil : session.screen()
                let snapshot = session.snapshot(previousMessages: streamed.messages, chat: chat, screen: screen, previousScreen: streamed.screen)
                let messages = session.transcript.messages
                let source = session.transcript.source
                try await RemoteChannel.send(RemoteEvent.terminal(snapshot), on: connection)
                streamed.screen = screen
                streamed.hasExited = snapshot.hasExited
                if chat { streamed.messages = messages; streamed.source = source }
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
            guard version == RemoteProtocol.version else { throw RemoteError(message: Self.incompatibleVersions) }
            return try .success(store.state)
        case .input(let id, let data, let message):
            try requireWritable()
            guard data.count <= 65_536, (message?.utf8.count ?? 0) <= 65_536 else { throw RemoteError(message: "Message trop long.") }
            try await startedSession(id).send(data, message: message)
            return try .success(true)
        case .newTerminal(let project, let worktree):
            try requireWritable()
            let launch = settings?.agentLaunch ?? AgentLaunch()
            let id = try store.addTerminal(projectID: project, worktreeID: worktree,
                                           command: launch.command(on: .newTerminal), select: false)
            return try .success(id.terminal.id)
        case .children(let id, let path):
            return try .fitting(await InspectorService.children(at: validatedURL(path, terminal: id))) { ExplorerListing(entries: $0, omitted: $1) }
        case .text(let id, let path):
            return try await .success(InspectorService.textFile(validatedURL(path, terminal: id)))
        case .git(let id):
            let local = try await InspectorService.localGit(at: context(id).worktree.path)
            return try .fitting(local.changes) {
                LocalGitSnapshot(root: local.root, branch: local.branch, headSHA: local.headSHA, changes: $0, omittedChanges: $1)
            }
        case .github(let id):
            let local = try await InspectorService.localGit(at: context(id).worktree.path, changesIn: [])
            return try await .success(InspectorService.remote(for: local))
        case .diff(let id, let change):
            let local = try await InspectorService.localGit(at: context(id).worktree.path,
                                                            changesIn: [change.path] + (change.originalPath.map { [$0] } ?? []))
            guard let actual = local.changes.first(where: { $0.path == change.path }) else { throw RemoteError(message: "Le fichier n’a plus de modifications.") }
            _ = try validatedURL(URL(fileURLWithPath: local.root).appendingPathComponent(actual.path).path, within: local.root)
            return try await .success(RemoteDiff(InspectorService.diff(actual, at: local.root)))
        case .conversations(let id, let fresh):
            return try await .success(ConversationIndex.load(at: context(id).worktree.path, runningMaximumAge: fresh ? .zero : .seconds(10)))
        case .launchAgent(let id, let agent):
            try requireWritable()
            let session = try startedSession(id)
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

    private func startedSession(_ id: UUID) throws -> TerminalSession {
        guard let store else { throw RemoteError(message: "Le Mac n’est pas prêt.") }
        _ = try context(id)
        guard let context = store.startableContext(for: id) else { throw RemoteError(message: "Ce worktree est en cours de suppression.") }
        return store.sessions.start(context)
    }

    private func validatedURL(_ path: String, terminal: UUID) throws -> URL {
        try validatedURL(path, within: context(terminal).worktree.path)
    }

    private func validatedURL(_ path: String, within rootPath: String) throws -> URL {
        let root = Self.resolved(rootPath)
        let url = Self.resolved(path)
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw RemoteError(message: "Le fichier est en dehors de ce worktree.")
        }
        return url
    }

    private static func resolved(_ path: String) -> URL {
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var missing: [String] = []
        while existing.path != "/", !FileManager.default.fileExists(atPath: existing.path) {
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
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
                let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if (try? RemoteProtocol.host(value)) != nil { addresses.append(value) }
            }
        }
        return Array(Set(addresses)).sorted()
    }
}
