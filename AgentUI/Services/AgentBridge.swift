import Foundation
import AppKit

@MainActor final class AgentBridge {
    let directory: URL
    private let store: WorkspaceStore
    private var watcher: FileSystemWatcher?
    private var active: Set<UUID> = []

    init(store: WorkspaceStore) throws {
        self.store = store
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("agentui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Self.installLauncher(at: bin.appendingPathComponent("agentui"))
        store.sessions.environment = [
            "AGENTUI_INSTANCE": directory.path,
            "AGENTUI_CLI": bin.appendingPathComponent("agentui").path,
            "PATH": bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        ]
        do {
            watcher = try FileSystemWatcher(directory, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.drain() }
            }
        } catch { throw WorkspaceError(message: String(localized: "Couldn’t set up the agentui command.")) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil {
            let stateDirectory = WorkspaceDisk.applicationDirectory
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            try directory.path.write(to: stateDirectory.appendingPathComponent("instance-path"), atomically: true, encoding: .utf8)
        }
        #endif
        publish()
    }

    private var registration: URL {
        WorkspaceDisk.instancesDirectory.appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier))
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: registration)
    }

    private func publish() {
        try? FileManager.default.createDirectory(at: WorkspaceDisk.instancesDirectory, withIntermediateDirectories: true)
        try? directory.path.write(to: registration, atomically: true, encoding: .utf8)
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
            guard request.id == id else { throw WorkspaceError(message: String(localized: "Invalid request ID.")) }
            var result = try await execute(request)
            if request.action != "list" && !request.action.hasPrefix("debug.") {
                do { try await store.flushPersistence() }
                catch { result.ok = false; result.message = error.localizedDescription }
            }
            response = result
        } catch { response = BridgeResponse(ok: false, message: error.localizedDescription) }
        do {
            try await BridgeMailbox.write(response, to: directory.appendingPathComponent("\(id.uuidString).response"))
        } catch { store.errorMessage = String(localized: "Couldn’t reply to agentui: \(error.localizedDescription)") }
    }

    private func execute(_ request: BridgeRequest) async throws -> BridgeResponse {
        #if DEBUG
        if request.action.hasPrefix("debug."), ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil {
            return try await DevelopmentCapture.execute(request, store: store)
        }
        #endif
        if request.action == "list" { return BridgeResponse(ok: true, workspace: store.state) }
        guard !store.isReadOnly else { throw WorkspaceError(message: String(localized: "The saved organization is unreadable. Fix it, then use Retry in the app before creating terminals.")) }
        if request.action == "project.add", let path = request.path {
            let project = try store.addProject(URL(fileURLWithPath: path))
            return BridgeResponse(ok: true, projectID: project.id, worktreeID: project.worktrees[0].id, path: project.path)
        }
        let location = location(of: request.directory)
        if request.action == "worktree.delete" { return try await deleteWorktree(request, currentLocation: location) }
        let request = resolvingContext(of: request, location: location)
        guard let projectID = request.projectID,
              let project = store.projects.first(where: { $0.id == projectID }) else {
            throw WorkspaceError(message: String(localized: "Project not found. Use --project UUID, or run the command from an AgentUI terminal or from the folder of a project open in AgentUI."))
        }
        let context: TerminalContext
        switch request.action {
        case "terminal.create":
            let worktreeID = request.worktreeID ?? project.worktrees[0].id
            context = try store.addTerminal(projectID: projectID, worktreeID: worktreeID, command: request.command, select: false)
            if let name = request.name { store.rename(context.terminal.id, to: name) }
        case "worktree.create":
            guard let branch = request.branch else { throw WorkspaceError(message: String(localized: "A branch name is required: --branch feature/my-task.")) }
            context = try await store.createWorktree(projectID: projectID, branch: branch, command: request.command, select: false)
            if let name = request.name { store.rename(context.terminal.id, to: name) }
        default:
            throw WorkspaceError(message: String(localized: "Unknown command: \(request.action)"))
        }
        return BridgeResponse(ok: true, projectID: context.project.id, worktreeID: context.worktree.id,
                              terminalID: context.terminal.id, path: context.worktree.path)
    }

    private func deleteWorktree(_ request: BridgeRequest, currentLocation: (projectID: UUID, worktreeID: UUID)?) async throws -> BridgeResponse {
        guard let worktreeID = request.worktreeID,
              let project = project(containing: worktreeID),
              let worktree = project.worktrees.first(where: { $0.id == worktreeID }) else {
            throw WorkspaceError(message: String(localized: "Worktree not found. Get its UUID with agentui list."))
        }
        if let projectID = request.projectID, projectID != project.id {
            throw WorkspaceError(message: String(localized: "This worktree doesn’t belong to the specified project."))
        }
        if currentLocation?.worktreeID == worktreeID {
            throw WorkspaceError(message: String(localized: "The current folder belongs to the worktree to delete. Run the command from another folder."))
        }
        if request.force != true, try await GitService.hasLocalChanges(at: worktree.path) {
            throw WorkspaceError(message: String(localized: "The worktree “\(worktree.displayName)” has uncommitted changes or untracked files. Run again with --force to erase them."))
        }
        guard request.deleteBranch == true || request.forceBranch == true else {
            try await store.deleteWorktree(projectID: project.id, worktreeID: worktreeID)
            return BridgeResponse(ok: true, projectID: project.id, worktreeID: worktreeID, path: worktree.path)
        }
        let cleanup = try await store.deleteWorktree(projectID: project.id, worktreeID: worktreeID, branch: request.forceBranch == true ? .force : .merged)
        return BridgeResponse(ok: cleanup.failure == nil, message: cleanup.failure ?? cleanup.notice, projectID: project.id, worktreeID: worktreeID,
                              path: worktree.path, branch: cleanup.branch, branchDeleted: cleanup.isDeleted)
    }

    private static func installLauncher(at url: URL) throws {
        let executable = Bundle.main.executableURL!.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\nexec '\(executable)' --cli \"$@\"\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func resolvingContext(of request: BridgeRequest, location: (projectID: UUID, worktreeID: UUID)?) -> BridgeRequest {
        guard request.projectID == nil else { return request }
        var request = request
        if let worktreeID = request.worktreeID {
            request.projectID = project(containing: worktreeID)?.id
        } else if let location {
            request.projectID = location.projectID
            request.worktreeID = location.worktreeID
        }
        return request
    }

    private func location(of directory: String?) -> (projectID: UUID, worktreeID: UUID)? {
        directory.flatMap { store.state.location(containing: WorkspacePath.canonical(URL(fileURLWithPath: $0))) }
    }

    private func project(containing worktreeID: UUID) -> Project? {
        store.projects.first { $0.worktrees.contains { $0.id == worktreeID } }
    }
}
