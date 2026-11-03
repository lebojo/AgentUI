import Foundation

struct CommandLineInstaller: Installer {
    static func load() async throws -> CommandLineInstaller {
        guard let executable = Bundle.main.executableURL else { throw WorkspaceError(message: String(localized: "Heka’s executable is missing.")) }
        return CommandLineInstaller(executable: executable, directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"))
    }
    static let commandName = "heka"
    private static let appExecutableSuffix = ".app/Contents/MacOS/Heka"

    let executable: URL
    let directory: URL

    var link: URL { directory.appending(path: Self.commandName) }

    var status: InstallationStatus {
        guard (try? FileManager.default.attributesOfItem(atPath: link.path)) != nil else { return .notInstalled }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return .conflict }
        if destination == executable.path { return .installed }
        return destination.hasSuffix(Self.appExecutableSuffix) ? .outdated : .conflict
    }

    func install() throws {
        let current = status
        guard current != .conflict else { throw WorkspaceError(message: String(localized: "\(link.path) already exists and doesn’t belong to Heka.")) }
        guard current != .installed else { return }
        guard !executable.path.contains("/AppTranslocation/") else {
            throw WorkspaceError(message: String(localized: "macOS is running Heka from a temporary copy. Move the app to the Applications folder, relaunch it, then try again."))
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
