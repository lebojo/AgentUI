import Foundation

enum AgentCLI {
    static let help = String(localized: """
    agentui — organize the terminals and worktrees of the running app

    agentui list
    agentui project add /path/to/project
    agentui terminal create [--name NAME] [--project UUID] [--worktree UUID] [-- COMMAND ARGUMENTS…]
    agentui worktree create --branch BRANCH [--name NAME] [--project UUID] [-- COMMAND ARGUMENTS…]
    agentui worktree delete --worktree UUID [--force]

    From an AgentUI terminal, the project and worktree are implicit.
    Child commands are passed as arguments, without shell interpretation.
    Examples:
      agentui terminal create --name Review -- claude "Review the changes"
      agentui worktree create --branch feature/tests -- codex "Add the tests"
    Each creation returns the identifiers and path as JSON.
    An existing branch is opened as is; otherwise it is created from the project’s HEAD.
    worktree delete closes its terminals and erases its folder; the branch and its commits stay in the repository.
    Without --force, a worktree with uncommitted changes or untracked files is kept.
    A project’s main folder and the current terminal’s worktree can’t be deleted.
    """)

    static func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(help)
            return 0
        }
        do {
            let environment = ProcessInfo.processInfo.environment
            guard let instance = environment["AGENTUI_INSTANCE"] else {
                throw WorkspaceError(message: String(localized: "Run agentui from a terminal in the app."))
            }
            let directory = URL(fileURLWithPath: instance)
            guard FileManager.default.fileExists(atPath: directory.path) else {
                throw WorkspaceError(message: String(localized: "This AgentUI instance is closed."))
            }
            let request = try parse(arguments, environment: environment)
            let requestURL = directory.appendingPathComponent("\(request.id.uuidString).request")
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response")
            defer { try? FileManager.default.removeItem(at: responseURL) }
            let changes = DispatchSemaphore(value: 0)
            let watcher = try? FileSystemWatcher(directory, queue: .global(qos: .userInitiated)) { _ in changes.signal() }
            defer { watcher?.cancel() }
            let recheck: DispatchTimeInterval = watcher == nil ? .milliseconds(50) : .seconds(1)
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            let deadline = DispatchTime.now() + 120
            while DispatchTime.now() < deadline {
                if FileManager.default.fileExists(atPath: responseURL.path) {
                    let data = try BridgeMailbox.contents(of: responseURL, as: .response)
                    let response = try JSONDecoder().decode(BridgeResponse.self, from: data)
                    print(String(decoding: data, as: UTF8.self))
                    return response.ok ? 0 : 1
                }
                if !FileManager.default.fileExists(atPath: directory.path) {
                    throw WorkspaceError(message: String(localized: "The app was closed before responding."))
                }
                _ = changes.wait(timeout: min(deadline, .now() + recheck))
            }
            throw WorkspaceError(message: String(localized: "AgentUI didn’t respond within 120 seconds. The operation may still be running; check agentui list before trying again."))
        } catch {
            let response = BridgeResponse(ok: false, message: error.localizedDescription)
            if let data = try? JSONEncoder().encode(response) { print(String(decoding: data, as: UTF8.self)) }
            return 1
        }
    }

    static func parse(_ arguments: [String], environment: [String: String]) throws -> BridgeRequest {
        var request = BridgeRequest(id: UUID(), action: "", projectID: environment["AGENTUI_PROJECT_ID"].flatMap(UUID.init(uuidString:)),
                                    worktreeID: environment["AGENTUI_WORKTREE_ID"].flatMap(UUID.init(uuidString:)), command: [])
        if arguments == ["list"] { request.action = "list"; return request }
        if arguments.count == 3, arguments[0...1] == ["project", "add"] {
            request.action = "project.add"
            request.path = URL(fileURLWithPath: arguments[2]).standardizedFileURL.path
            return request
        }
        let commands = [["terminal", "create"], ["worktree", "create"], ["worktree", "delete"]]
        guard arguments.count >= 2, commands.contains(Array(arguments[0...1])) else {
            throw WorkspaceError(message: String(localized: "Unknown command. See agentui --help."))
        }
        request.action = arguments[0] + "." + arguments[1]
        let isDeletion = request.action == "worktree.delete"
        let currentWorktreeID = request.worktreeID
        let explicitlyTargetsProject = arguments.prefix(while: { $0 != "--" }).contains("--project")
        if explicitlyTargetsProject || isDeletion { request.worktreeID = nil }
        var index = 2
        while index < arguments.count {
            let option = arguments[index]
            if option == "--" && !isDeletion { request.command = Array(arguments.dropFirst(index + 1)); break }
            if option == "--force" && isDeletion { request.force = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw WorkspaceError(message: String(localized: "Missing value for \(option).")) }
            let value = arguments[index + 1]
            switch option {
            case "--name": request.name = value
            case "--branch": request.branch = value
            case "--project":
                guard let id = UUID(uuidString: value) else { throw WorkspaceError(message: String(localized: "Invalid project UUID.")) }
                request.projectID = id
            case "--worktree":
                guard let id = UUID(uuidString: value) else { throw WorkspaceError(message: String(localized: "Invalid worktree UUID.")) }
                request.worktreeID = id
            default: throw WorkspaceError(message: String(localized: "Unknown option: \(option)"))
            }
            index += 2
        }
        if isDeletion {
            guard let target = request.worktreeID else {
                throw WorkspaceError(message: String(localized: "Specify the worktree to delete: --worktree UUID (see agentui list)."))
            }
            if target == currentWorktreeID {
                throw WorkspaceError(message: String(localized: "This terminal belongs to the worktree being deleted. Run the command from another worktree."))
            }
        }
        return request
    }
}
