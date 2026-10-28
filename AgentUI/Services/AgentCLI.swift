import Foundation

/// Run before SwiftUI starts, when the executable is invoked via the agentui symlink.
enum AgentCLI {
    static let help = """
    agentui — organiser les terminaux et worktrees de l’application ouverte

    agentui list
    agentui project add /chemin/du/projet
    agentui terminal create [--name NOM] [--project UUID] [--worktree UUID] [-- COMMANDE ARGUMENTS…]
    agentui worktree create --branch BRANCHE [--name NOM] [--project UUID] [-- COMMANDE ARGUMENTS…]

    Depuis un terminal AgentUI, le projet et le worktree sont implicites.
    Les commandes enfant sont passées comme arguments, sans interprétation shell.
    Exemples :
      agentui terminal create --name Review -- claude "Relis les modifications"
      agentui worktree create --branch feature/tests -- codex "Ajoute les tests"
    Chaque création renvoie les identifiants et le chemin au format JSON.
    Une branche existante est ouverte telle quelle ; sinon elle est créée depuis le HEAD du projet.
    """

    static func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(help)
            return 0
        }
        do {
            let environment = ProcessInfo.processInfo.environment
            guard let instance = environment["AGENTUI_INSTANCE"] else {
                throw WorkspaceError(message: "Exécute agentui depuis un terminal de l’application.")
            }
            let directory = URL(fileURLWithPath: instance)
            guard FileManager.default.fileExists(atPath: directory.path) else {
                throw WorkspaceError(message: "Cette instance d’AgentUI est fermée.")
            }
            let request = try parse(arguments, environment: environment)
            let requestURL = directory.appendingPathComponent("\(request.id.uuidString).request")
            let responseURL = directory.appendingPathComponent("\(request.id.uuidString).response")
            defer { try? FileManager.default.removeItem(at: responseURL) }
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                if let data = try? Data(contentsOf: responseURL) {
                    let response = try JSONDecoder().decode(BridgeResponse.self, from: data)
                    print(String(decoding: data, as: UTF8.self))
                    return response.ok ? 0 : 1
                }
                if !FileManager.default.fileExists(atPath: directory.path) {
                    throw WorkspaceError(message: "L’application a été fermée avant la réponse.")
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            throw WorkspaceError(message: "AgentUI n’a pas répondu sous 120 secondes. L’opération peut continuer ; vérifie agentui list avant de réessayer.")
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
        guard arguments.count >= 2, ["terminal", "worktree"].contains(arguments[0]), arguments[1] == "create" else {
            throw WorkspaceError(message: "Commande inconnue. Consulte agentui --help.")
        }
        request.action = arguments[0] + ".create"
        let explicitlyTargetsProject = arguments.prefix(while: { $0 != "--" }).contains("--project")
        if explicitlyTargetsProject { request.worktreeID = nil }
        var index = 2
        while index < arguments.count {
            let option = arguments[index]
            if option == "--" { request.command = Array(arguments.dropFirst(index + 1)); break }
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
        return request
    }
}
