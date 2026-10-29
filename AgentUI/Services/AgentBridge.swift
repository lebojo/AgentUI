import Foundation
import AppKit

@MainActor final class AgentBridge {
    let directory: URL
    private let store: WorkspaceStore
    private var source: DispatchSourceFileSystemObject?
    private var active: Set<UUID> = []
    private var descriptor: Int32 = -1

    init(store: WorkspaceStore) throws {
        self.store = store
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("agentui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("agentui"), withDestinationURL: Bundle.main.executableURL!)
        store.sessions.environment = [
            "AGENTUI_INSTANCE": directory.path,
            "AGENTUI_CLI": bin.appendingPathComponent("agentui").path,
            "PATH": bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        ]
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw WorkspaceError(message: "Impossible d’initialiser la commande agentui.") }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in self?.drain() }
        let fd = descriptor
        watcher.setCancelHandler { close(fd) }
        source = watcher
        watcher.resume()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil {
            let stateDirectory = WorkspaceDisk.applicationDirectory
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            try directory.path.write(to: stateDirectory.appendingPathComponent("instance-path"), atomically: true, encoding: .utf8)
        }
        #endif
    }

    func stop() {
        source?.cancel()
        source = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func drain() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "request" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !active.contains(id) else { continue }
            active.insert(id)
            Task { await process(file, id: id) }
        }
    }

    private func process(_ file: URL, id: UUID) async {
        defer { active.remove(id); try? FileManager.default.removeItem(at: file) }
        let response: BridgeResponse
        do {
            let request = try await BridgeMailbox.request(at: file)
            guard request.id == id else { throw WorkspaceError(message: "Identifiant de requête invalide.") }
            var result = try await execute(request)
            if request.action != "list" && !request.action.hasPrefix("debug.") {
                do { try await store.flushPersistence() }
                catch { result.ok = false; result.message = error.localizedDescription }
            }
            response = result
        } catch { response = BridgeResponse(ok: false, message: error.localizedDescription) }
        do {
            try await BridgeMailbox.write(response, to: directory.appendingPathComponent("\(id.uuidString).response"))
        } catch { store.errorMessage = "Impossible de répondre à agentui : \(error.localizedDescription)" }
    }

    private func execute(_ request: BridgeRequest) async throws -> BridgeResponse {
        #if DEBUG
        if request.action.hasPrefix("debug."), ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil {
            return try await DevelopmentCapture.execute(request, store: store)
        }
        #endif
        if request.action == "list" { return BridgeResponse(ok: true, workspace: store.state) }
        guard !store.isReadOnly else { throw WorkspaceError(message: "L’organisation enregistrée est illisible. Répare-la puis utilise Réessayer dans l’application avant de créer des terminaux.") }
        if request.action == "project.add", let path = request.path {
            let project = try store.addProject(URL(fileURLWithPath: path))
            return BridgeResponse(ok: true, projectID: project.id, worktreeID: project.worktrees[0].id, path: project.path)
        }
        guard let projectID = request.projectID,
              let project = store.projects.first(where: { $0.id == projectID }) else {
            throw WorkspaceError(message: "Projet introuvable. Utilise --project UUID ou exécute la commande dans un terminal AgentUI.")
        }
        let context: TerminalContext
        switch request.action {
        case "terminal.create":
            let worktreeID = request.worktreeID ?? project.worktrees[0].id
            context = try store.addTerminal(projectID: projectID, worktreeID: worktreeID, name: request.name ?? "Terminal",
                                            command: request.command, select: false)
        case "worktree.create":
            guard let branch = request.branch else { throw WorkspaceError(message: "Le nom de branche est requis : --branch feature/ma-tache.") }
            context = try await store.createWorktree(projectID: projectID, branch: branch, command: request.command, select: false)
            if let name = request.name { store.rename(context.terminal.id, to: name) }
        default:
            throw WorkspaceError(message: "Commande inconnue : \(request.action)")
        }
        return BridgeResponse(ok: true, projectID: context.project.id, worktreeID: context.worktree.id,
                              terminalID: context.terminal.id, path: context.worktree.path)
    }
}
