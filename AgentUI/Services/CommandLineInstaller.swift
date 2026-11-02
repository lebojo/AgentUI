import Foundation

struct CommandLineInstaller: Installer {
    static func load() async throws -> CommandLineInstaller {
        guard let executable = Bundle.main.executableURL else { throw WorkspaceError(message: "L’exécutable d’AgentUI est introuvable.") }
        return CommandLineInstaller(executable: executable, directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"))
    }
    private static let appExecutableSuffix = ".app/Contents/MacOS/AgentUI"

    let executable: URL
    let directory: URL

    var link: URL { directory.appending(path: "agentui") }

    var status: InstallationStatus {
        guard (try? FileManager.default.attributesOfItem(atPath: link.path)) != nil else { return .notInstalled }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return .conflict }
        if destination == executable.path { return .installed }
        return destination.hasSuffix(Self.appExecutableSuffix) ? .outdated : .conflict
    }

    func install() throws {
        let current = status
        guard current != .conflict else { throw WorkspaceError(message: "\(link.path) existe déjà et n’appartient pas à AgentUI.") }
        guard current != .installed else { return }
        guard !executable.path.contains("/AppTranslocation/") else {
            throw WorkspaceError(message: "macOS exécute AgentUI depuis une copie temporaire. Déplace l’app dans le dossier Applications, relance-la, puis réessaie.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if current == .outdated { try FileManager.default.removeItem(atPath: link.path) }
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: executable.path)
    }

    func uninstall() throws {
        guard status.canUninstall else { return }
        try FileManager.default.removeItem(atPath: link.path)
    }
}
