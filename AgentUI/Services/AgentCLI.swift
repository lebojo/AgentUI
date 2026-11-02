import Foundation

enum AgentCLI {
    static let help = """
    agentui — organiser les terminaux et worktrees de l’application ouverte

    agentui list
    agentui project add /chemin/du/projet
    agentui terminal create [--name NOM] [--project UUID] [--worktree UUID] [-- COMMANDE ARGUMENTS…]
    agentui worktree create --branch BRANCHE [--name NOM] [--project UUID] [-- COMMANDE ARGUMENTS…]
    agentui worktree delete --worktree UUID [--force]

    Depuis un terminal AgentUI, le projet et le worktree sont implicites.
    Ailleurs, ils sont déduits du dossier courant s’il appartient à un projet ouvert dans AgentUI.
    Les commandes enfant sont passées comme arguments, sans interprétation shell.
    Exemples :
      agentui terminal create --name Review -- claude "Relis les modifications"
      agentui worktree create --branch feature/tests -- codex "Ajoute les tests"
    Chaque création renvoie les identifiants et le chemin au format JSON.
    Une branche existante est ouverte telle quelle ; sinon elle est créée depuis le HEAD du projet.
    worktree delete ferme ses terminaux et efface son dossier ; la branche et ses commits restent dans le dépôt.
    Sans --force, un worktree avec des modifications non commitées ou des fichiers non suivis est conservé.
    Le dossier principal d’un projet et le worktree du terminal courant ne peuvent pas être supprimés.
    """

    static func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(help)
            return 0
        }
        do {
            let environment = ProcessInfo.processInfo.environment
            let directory = try instanceDirectory(environment: environment)
            let request = try parse(arguments, environment: environment, currentDirectory: FileManager.default.currentDirectoryPath)
            let requestURL = directory.appendingPathComponent("\(request.id.uuidString).request")
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response")
            defer { try? FileManager.default.removeItem(at: responseURL) }
            let changes = DispatchSemaphore(value: 0)
            let watcher = try? DirectoryWatcher(directory, queue: .global(qos: .userInitiated)) { changes.signal() }
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
                    throw WorkspaceError(message: "L’application a été fermée avant la réponse.")
                }
                _ = changes.wait(timeout: min(deadline, .now() + recheck))
            }
            throw WorkspaceError(message: "AgentUI n’a pas répondu sous 120 secondes. L’opération peut continuer ; vérifie agentui list avant de réessayer.")
        } catch {
            let response = BridgeResponse(ok: false, message: error.localizedDescription)
            if let data = try? JSONEncoder().encode(response) { print(String(decoding: data, as: UTF8.self)) }
            return 1
        }
    }

    static func instanceDirectory(environment: [String: String]) throws -> URL {
        if let instance = environment["AGENTUI_INSTANCE"] {
            guard FileManager.default.fileExists(atPath: instance) else { throw WorkspaceError(message: "Cette instance d’AgentUI est fermée.") }
            return URL(fileURLWithPath: instance)
        }
        guard let published = runningInstance(in: WorkspaceDisk.instancesDirectory) else {
            throw WorkspaceError(message: "AgentUI n’est pas ouvert. Lance l’application puis réessaie.")
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
        let commands = [["terminal", "create"], ["worktree", "create"], ["worktree", "delete"]]
        guard arguments.count >= 2, commands.contains(Array(arguments[0...1])) else {
            throw WorkspaceError(message: "Commande inconnue. Consulte agentui --help.")
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
            guard index + 1 < arguments.count else { throw WorkspaceError(message: "Valeur manquante pour \(option).") }
            let value = arguments[index + 1]
            switch option {
            case "--name": request.name = value
            case "--branch": request.branch = value
            case "--project":
                guard let id = UUID(uuidString: value) else { throw WorkspaceError(message: "UUID de projet invalide.") }
                request.projectID = id
            case "--worktree":
                guard let id = UUID(uuidString: value) else { throw WorkspaceError(message: "UUID de worktree invalide.") }
                request.worktreeID = id
            default: throw WorkspaceError(message: "Option inconnue : \(option)")
            }
            index += 2
        }
        if isDeletion {
            guard let target = request.worktreeID else {
                throw WorkspaceError(message: "Indique le worktree à supprimer : --worktree UUID (voir agentui list).")
            }
            if target == currentWorktreeID {
                throw WorkspaceError(message: "Ce terminal appartient au worktree à supprimer. Lance la commande depuis un autre worktree.")
            }
        }
        return request
    }
}
