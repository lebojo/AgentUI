import Foundation

enum WorkspaceDisk {
    static var applicationDirectory: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["HEKA_STATE_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return defaultApplicationDirectory
    }

    static var instancesDirectory: URL {
        applicationDirectory.appendingPathComponent("Instances", isDirectory: true)
    }

    static var worktreesDirectory: URL {
        testWorktreesDirectory ?? storedWorktreesDirectory(in: .standard)
    }

    static var testWorktreesDirectory: URL? {
        usesTestState ? applicationDirectory.appendingPathComponent("Worktrees", isDirectory: true) : nil
    }

    static var usesTestState: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["HEKA_STATE_DIRECTORY"] != nil
        #else
        false
        #endif
    }

    static let worktreesDirectoryKey = "settings.worktreesDirectory"
    static let scannedWorktreesDirectoriesKey = "settings.scannedWorktreesDirectories"

    static var defaultWorktreesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".heka", isDirectory: true)
    }

    static func storedWorktreesDirectory(in defaults: UserDefaults) -> URL {
        defaults.string(forKey: worktreesDirectoryKey).flatMap(directory) ?? defaultWorktreesDirectory
    }

    static func storedScannedWorktreesDirectories(in defaults: UserDefaults) -> [URL] {
        (defaults.stringArray(forKey: scannedWorktreesDirectoriesKey) ?? []).compactMap(directory)
    }

    static let legacyWorktreesDirectories = [
        (name: "agentui", checkedKey: "settings.legacyWorktreesDirectoryChecked"),
        (name: ".agentui", checkedKey: "settings.hiddenLegacyWorktreesDirectoryChecked"),
    ]

    static func scanLegacyWorktreesDirectories(in defaults: UserDefaults) {
        for legacy in legacyWorktreesDirectories {
            scanLegacyWorktreesDirectory(legacyWorktreesDirectory(named: legacy.name), checkedKey: legacy.checkedKey, in: defaults)
        }
    }

    static func isLegacyWorktreesDirectory(_ path: String) -> Bool {
        guard let url = directory(path) else { return false }
        return legacyWorktreesDirectories.contains { legacyWorktreesDirectory(named: $0.name).standardizedFileURL == url }
    }

    private static func legacyWorktreesDirectory(named name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true)
    }

    static func scanLegacyWorktreesDirectory(_ legacy: URL, checkedKey: String, in defaults: UserDefaults) {
        guard !defaults.bool(forKey: checkedKey) else { return }
        defaults.set(true, forKey: checkedKey)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacy.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let scanned = defaults.stringArray(forKey: scannedWorktreesDirectoriesKey) ?? []
        let known = ([storedWorktreesDirectory(in: defaults)] + storedScannedWorktreesDirectories(in: defaults)).map(\.path)
        guard !known.contains(legacy.standardizedFileURL.path) else { return }
        defaults.set(scanned + [legacy.standardizedFileURL.path], forKey: scannedWorktreesDirectoriesKey)
    }

    private static func directory(_ path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    static var legacyApplicationDirectory: URL { applicationSupport(named: "AgentUI") }

    private static var defaultApplicationDirectory: URL { applicationSupport(named: "Heka") }

    private static func applicationSupport(named name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name, isDirectory: true)
    }

    static func load(from url: URL) throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let state = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        guard state.version == 1 else {
            throw WorkspaceError(message: String(localized: "This organization uses a newer version of Heka."))
        }
        return state
    }

    static func save(_ state: Workspace, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    static func childDirectories(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])
            .filter {
                let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values.isDirectory == true && values.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
