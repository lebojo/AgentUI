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
            if !Self.leavesWorkspaceUnchanged(request.action) {
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
        switch request.action {
        case "terminal.send": return try await sendInput(request)
        case "terminal.read": return try await readOutput(request)
        case "terminal.wait": return try await waitForTerminal(request)
        default: break
        }
        guard !store.isReadOnly else { throw WorkspaceError(message: String(localized: "The saved organization is unreadable. Fix it, then use Retry in the app before creating terminals.")) }
        if request.action == "project.add", let path = request.path {
            let project = try store.addProject(URL(fileURLWithPath: path))
            return BridgeResponse(ok: true, projectID: project.id, worktreeID: project.worktrees[0].id, path: project.path)
        }
        if request.action == "terminal.close" { return try await closeTerminal(request) }
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
        let branchRemoval = try request.branchRemoval
        if request.force != true, try await GitService.hasLocalChanges(at: worktree.path) {
            throw WorkspaceError(message: String(localized: "The worktree “\(worktree.displayName)” has uncommitted changes or untracked files. Run again with --force to erase them."))
        }
        let cleanup: BranchCleanup
        do {
            cleanup = try await store.deleteWorktree(projectID: project.id, worktreeID: worktreeID, branch: branchRemoval)
        } catch let error as UnmergedBranchError {
            throw WorkspaceError(message: String(localized: "\(error.localizedDescription) Run again with --force-branch to delete it anyway, or without --delete-branch to keep it."))
        }
        return BridgeResponse(deleting: worktree, of: project.id, cleanup: cleanup)
    }

    private static func leavesWorkspaceUnchanged(_ action: String) -> Bool {
        ["list", "terminal.send", "terminal.read", "terminal.wait"].contains(action) || action.hasPrefix("debug.")
    }

    private func sendInput(_ request: BridgeRequest) async throws -> BridgeResponse {
        let id = try existingTerminal(request.terminalID)
        guard let context = store.startableContext(for: id) else { throw WorkspaceError(message: String(localized: "This worktree is being deleted.")) }
        let session = store.sessions.start(context)
        if let keys = request.keys {
            try await session.press(keys.compactMap(TerminalKey.init(name:)), from: .remote)
        } else {
            try await session.type(request.text ?? "", submitting: request.pressesEnter == true, from: .remote)
        }
        return await state(of: id)
    }

    private func readOutput(_ request: BridgeRequest) async throws -> BridgeResponse {
        let id = try existingTerminal(request.terminalID)
        var response = await state(of: id)
        let session = store.sessions.session(id)
        guard request.reply == true || request.messages != nil else {
            response.output = session?.recentLines(request.lines ?? TerminalWait.defaultLines) ?? ""
            return response
        }
        guard let session else { throw WorkspaceError(message: String(localized: "This terminal isn’t running.")) }
        let conversation = try await session.conversation()
        if let count = request.messages {
            response.messages = Array(conversation.suffix(count))
        } else {
            response.output = Self.reply(in: conversation)
        }
        return response
    }

    private static func reply(in conversation: [SessionMessage]) -> String {
        let start = conversation.lastIndex { $0.kind == .input }.map { $0 + 1 } ?? conversation.startIndex
        return conversation[start...].filter { $0.kind == .assistant }.map(\.text).joined(separator: "\n\n")
    }

    private func closeTerminal(_ request: BridgeRequest) async throws -> BridgeResponse {
        let id = try existingTerminal(request.terminalID)
        guard store.startableContext(for: id) != nil else { throw WorkspaceError(message: String(localized: "This worktree is being deleted.")) }
        var response = await state(of: id)
        if request.force != true, response.status == AgentStatus.working.identifier {
            throw WorkspaceError(message: String(localized: "The agent in this terminal is working. Wait for it with agentui terminal wait, or run again with --force to stop it."))
        }
        store.closeTerminal(id)
        response.running = false
        response.removed = true
        return response
    }

    private func waitForTerminal(_ request: BridgeRequest) async throws -> BridgeResponse {
        let id = try existingTerminal(request.terminalID)
        let timeout = request.timeoutSeconds ?? TerminalWait.defaultTimeout
        let idle = request.waitsForExit == true ? nil : request.idleSeconds ?? TerminalWait.defaultIdle
        let start = Date.now
        while let session = store.sessions.session(id), !session.hasExited {
            if let idle, Date.now.timeIntervalSince(max(session.lastOutput, start)) >= idle { break }
            guard Date.now.timeIntervalSince(start) < timeout else {
                var response = await state(of: id)
                response.ok = false
                response.message = idle == nil
                    ? String(localized: "The terminal’s command is still running after \(Int(timeout)) seconds.")
                    : String(localized: "The terminal is still printing output after \(Int(timeout)) seconds.")
                return response
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        return await state(of: id)
    }

    private func existingTerminal(_ id: UUID?) throws -> UUID {
        guard let id, let context = store.context(for: id), !context.isFloating else {
            throw WorkspaceError(message: String(localized: "Terminal not found. Get its UUID with agentui list."))
        }
        return id
    }

    private func state(of id: UUID) async -> BridgeResponse {
        await store.sessions.refreshAgents()
        let context = store.context(for: id)
        let session = store.sessions.session(id)
        return BridgeResponse(ok: true, projectID: context?.project.id, worktreeID: context?.worktree.id, terminalID: id,
                              path: context?.worktree.path, running: session.map { !$0.hasExited } ?? false,
                              exitCode: session?.exitCode, agent: session?.agentKind, status: session?.agentStatus?.identifier)
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
