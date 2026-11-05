import Foundation

enum AgentCLI {
    static let help = String(localized: """
    agentui — organize the terminals and worktrees of the running app

    agentui list
    agentui project add /path/to/project
    agentui terminal create [--name NAME] [--project UUID] [--worktree UUID] [-- COMMAND ARGUMENTS…]
    agentui worktree create --branch BRANCH [--name NAME] [--project UUID] [-- COMMAND ARGUMENTS…]
    agentui worktree delete --worktree UUID [--delete-branch [--force-branch]] [--force]
    agentui terminal send --terminal UUID [--enter] (-- TEXT… | --stdin)
    agentui terminal read --terminal UUID [--lines N]
    agentui terminal wait --terminal UUID [--idle SECONDS | --exit] [--timeout SECONDS]

    From an AgentUI terminal, the project and worktree are implicit.
    Elsewhere, they are inferred from the current folder if it belongs to a project open in AgentUI.
    Child commands are passed as arguments, without shell interpretation.
    Examples:
      agentui terminal create --name Review -- claude "Review the changes"
      agentui worktree create --branch feature/tests -- codex "Add the tests"
    Each creation returns the identifiers and path as JSON.
    An existing branch is opened as is; otherwise it is created from the project’s HEAD.
    worktree delete closes its terminals and erases its folder; by default, the branch and its commits stay in the repository.
    With --delete-branch, the branch is deleted too if it’s merged into the repository’s main branch; otherwise nothing is removed. Add --force-branch to delete it even if it isn’t, losing its unmerged commits.
    The repository’s main branch and a branch checked out elsewhere are never deleted.
    Without --force, a worktree with uncommitted changes or untracked files is kept; --force never deletes an unmerged branch.
    A project’s main folder and the current terminal’s worktree can’t be deleted.
    terminal send types TEXT into another terminal, or the standard input with --stdin. With --enter, the text is submitted as one message, like pressing Return; --enter alone just presses Return.
    terminal read prints the last lines of a terminal (50 by default, 10,000 at most) as output.
    terminal wait returns once the terminal has printed nothing for --idle SECONDS (5 by default), or once its command has exited with --exit. It gives up after --timeout SECONDS (120 by default, 3,600 at most) with ok: false.
    Their replies include running, exitCode and, for a recognized agent, agent and status (working, ready or waitingForInput).
    The current terminal can’t send to or wait for itself.
    """)

    static func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(help)
            return 0
        }
        do {
            let environment = ProcessInfo.processInfo.environment
            let directory = try instanceDirectory(environment: environment)
            var request = try parse(arguments, environment: environment, currentDirectory: FileManager.default.currentDirectoryPath)
            if request.action == "terminal.send", request.text == nil, arguments.contains("--stdin") { request.text = try standardInput() }
            let requestURL = directory.appendingPathComponent("\(request.id.uuidString).request")
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response")
            defer { try? FileManager.default.removeItem(at: responseURL) }
            let changes = DispatchSemaphore(value: 0)
            let watcher = try? FileSystemWatcher(directory, queue: .global(qos: .userInitiated)) { _ in changes.signal() }
            defer { watcher?.cancel() }
            let recheck: DispatchTimeInterval = watcher == nil ? .milliseconds(50) : .seconds(1)
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            let deadline = DispatchTime.now() + request.responseTimeout
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
            throw WorkspaceError(message: String(localized: "AgentUI didn’t respond within \(Int(request.responseTimeout)) seconds. The operation may still be running; check agentui list before trying again."))
        } catch {
            let response = BridgeResponse(ok: false, message: error.localizedDescription)
            if let data = try? JSONEncoder().encode(response) { print(String(decoding: data, as: UTF8.self)) }
            return 1
        }
    }

    private static func standardInput() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw WorkspaceError(message: String(localized: "The standard input isn’t UTF-8 text."))
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    static func instanceDirectory(environment: [String: String]) throws -> URL {
        if let instance = environment["AGENTUI_INSTANCE"], FileManager.default.fileExists(atPath: instance) {
            return URL(fileURLWithPath: instance)
        }
        guard let published = runningInstance(in: WorkspaceDisk.instancesDirectory) else {
            throw WorkspaceError(message: String(localized: "AgentUI isn’t open. Launch the app, then try again."))
        }
        return published
    }

    static func runningInstance(in registry: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(at: registry, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let running = entries.filter { entry in
            guard let pid = pid_t(entry.lastPathComponent) else { return false }
            guard isRunning(pid), let path = try? String(contentsOf: entry, encoding: .utf8),
                  FileManager.default.fileExists(atPath: path) else {
                try? FileManager.default.removeItem(at: entry)
                return false
            }
            return true
        }
        let newest = running.max { modificationDate(of: $0) < modificationDate(of: $1) }
        return newest.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map { URL(fileURLWithPath: $0) }
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func parse(_ arguments: [String], environment: [String: String], currentDirectory: String? = nil) throws -> BridgeRequest {
        var request = BridgeRequest(id: UUID(), action: "", projectID: environment["AGENTUI_PROJECT_ID"].flatMap(UUID.init(uuidString:)),
                                    worktreeID: environment["AGENTUI_WORKTREE_ID"].flatMap(UUID.init(uuidString:)), command: [])
        request.directory = currentDirectory
        if arguments == ["list"] { request.action = "list"; return request }
        if arguments.count == 3, arguments[0...1] == ["project", "add"] {
            request.action = "project.add"
            request.path = URL(fileURLWithPath: arguments[2]).standardizedFileURL.path
            return request
        }
        if arguments.count >= 2, ["send", "read", "wait"].contains(arguments[1]), arguments[0] == "terminal" {
            return try parseTerminalCommand(arguments, into: request, callerID: environment["AGENTUI_TERMINAL_ID"].flatMap(UUID.init(uuidString:)))
        }
        let commands = [["terminal", "create"], ["worktree", "create"], ["worktree", "delete"]]
        guard arguments.count >= 2, commands.contains(Array(arguments[0...1])) else {
            throw WorkspaceError(message: String(localized: "Unknown command. See agentui --help."))
        }
        request.action = arguments[0] + "." + arguments[1]
        let isDeletion = request.action == "worktree.delete"
        let currentWorktreeID = request.worktreeID
        let options = arguments.prefix { $0 != "--" }
        let explicitlyTargetsProject = options.contains("--project")
        if explicitlyTargetsProject || isDeletion { request.worktreeID = nil }
        if options.contains("--worktree") && !explicitlyTargetsProject { request.projectID = nil }
        var index = 2
        while index < arguments.count {
            let option = arguments[index]
            if option == "--" && !isDeletion { request.command = Array(arguments.dropFirst(index + 1)); break }
            if option == "--force" && isDeletion { request.force = true; index += 1; continue }
            if option == "--delete-branch" && isDeletion { request.deleteBranch = true; index += 1; continue }
            if option == "--force-branch" && isDeletion { request.forceBranch = true; index += 1; continue }
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
            _ = try request.branchRemoval
            guard let target = request.worktreeID else {
                throw WorkspaceError(message: String(localized: "Specify the worktree to delete: --worktree UUID (see agentui list)."))
            }
            if target == currentWorktreeID {
                throw WorkspaceError(message: String(localized: "This terminal belongs to the worktree being deleted. Run the command from another worktree."))
            }
        }
        return request
    }

    private static func parseTerminalCommand(_ arguments: [String], into base: BridgeRequest, callerID: UUID?) throws -> BridgeRequest {
        var request = base
        request.action = "terminal." + arguments[1]
        request.projectID = nil
        request.worktreeID = nil
        var readsInput = false
        var index = 2
        while index < arguments.count {
            let option = arguments[index]
            switch (request.action, option) {
            case ("terminal.send", "--"):
                request.text = arguments.dropFirst(index + 1).joined(separator: " ")
                index = arguments.count
                continue
            case ("terminal.send", "--enter"): request.pressesEnter = true; index += 1; continue
            case ("terminal.send", "--stdin"): readsInput = true; index += 1; continue
            case ("terminal.wait", "--exit"): request.waitsForExit = true; index += 1; continue
            default: break
            }
            guard index + 1 < arguments.count else { throw WorkspaceError(message: String(localized: "Missing value for \(option).")) }
            let value = arguments[index + 1]
            switch (request.action, option) {
            case (_, "--terminal"):
                guard let id = UUID(uuidString: value) else { throw WorkspaceError(message: String(localized: "Invalid terminal UUID.")) }
                request.terminalID = id
            case ("terminal.read", "--lines"):
                guard let lines = Int(value), (1...TerminalWait.maximumLines).contains(lines) else {
                    throw WorkspaceError(message: String(localized: "--lines must be a whole number from 1 to \(TerminalWait.maximumLines).")) }
                request.lines = lines
            case ("terminal.wait", "--idle"):
                request.idleSeconds = try seconds(value, option: option, maximum: TerminalWait.maximumTimeout)
            case ("terminal.wait", "--timeout"):
                request.timeoutSeconds = try seconds(value, option: option, maximum: TerminalWait.maximumTimeout)
            default: throw WorkspaceError(message: String(localized: "Unknown option: \(option)"))
            }
            index += 2
        }
        guard let target = request.terminalID else {
            throw WorkspaceError(message: String(localized: "Specify the terminal: --terminal UUID (see agentui list)."))
        }
        if request.waitsForExit == true, request.idleSeconds != nil {
            throw WorkspaceError(message: String(localized: "Use either --idle or --exit, not both."))
        }
        if readsInput, request.text != nil {
            throw WorkspaceError(message: String(localized: "Use either --stdin or text after --, not both."))
        }
        if request.action == "terminal.send", !readsInput, request.text?.isEmpty ?? true, request.pressesEnter != true {
            throw WorkspaceError(message: String(localized: "Nothing to send: add the text after --, or --stdin, or --enter."))
        }
        if target == callerID, request.action != "terminal.read" {
            throw WorkspaceError(message: String(localized: "This is the current terminal. Pass the UUID of another terminal."))
        }
        return request
    }

    private static func seconds(_ value: String, option: String, maximum: Double) throws -> Double {
        guard let seconds = Double(value), seconds.isFinite, seconds > 0, seconds <= maximum else {
            throw WorkspaceError(message: String(localized: "\(option) must be a number of seconds greater than 0 and at most \(Int(maximum))."))
        }
        return seconds
    }
}
