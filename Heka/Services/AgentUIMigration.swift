import AppKit

enum AgentUIMigration {
    private static let bundleIdentifier = "ch.jordanchap.agentui"
    private static let completedKey = "migration.agentUICompleted"
    private static let transientItems: Set<String> = ["Instances", ".DS_Store"]
    private static let mergedListKeys: Set<String> = [WorkspaceDisk.scannedWorktreesDirectoriesKey]

    static func run(defaults: UserDefaults = .standard) {
        guard !WorkspaceDisk.usesTestState, !defaults.bool(forKey: completedKey) else { return }
        let legacy = WorkspaceDisk.legacyApplicationDirectory
        guard !legacySettings(in: defaults).isEmpty || FileManager.default.fileExists(atPath: legacy.path) else {
            return defaults.set(true, forKey: completedKey)
        }
        guard agentUIHasQuit() else { return }
        importSettings(from: legacySettings(in: defaults), into: defaults)
        let leftBehind = moveContents(of: legacy, to: WorkspaceDisk.applicationDirectory)
        defaults.set(true, forKey: completedKey)
        guard !leftBehind.isEmpty else { return }
        notify(String(localized: "Some AgentUI data stayed behind"),
               String(localized: "Heka already had its own copy of these items or couldn’t move them. They stay in \(legacy.path): \(leftBehind.joined(separator: ", "))."))
    }

    static func importSettings(from legacy: [String: Any], into defaults: UserDefaults) {
        for (key, value) in legacy where !isLegacyWorktreesDirectory(key: key, value: value) {
            guard let current = defaults.object(forKey: key) else {
                defaults.set(value, forKey: key)
                continue
            }
            guard mergedListKeys.contains(key), let current = current as? [String], let value = value as? [String] else { continue }
            defaults.set(current + value.filter { !current.contains($0) }, forKey: key)
        }
    }

    static func moveContents(of legacy: URL, to destination: URL) -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacy.path) else { return [] }
        guard let items = try? fileManager.contentsOfDirectory(atPath: legacy.path) else { return [legacy.lastPathComponent] }
        let movable = items.filter { !transientItems.contains($0) }.sorted()
        guard (try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)) != nil else { return movable }
        return movable.filter { item in
            (try? fileManager.moveItem(at: legacy.appending(path: item), to: destination.appending(path: item))) == nil
        }
    }

    private static func legacySettings(in defaults: UserDefaults) -> [String: Any] {
        defaults.persistentDomain(forName: bundleIdentifier) ?? [:]
    }

    private static func isLegacyWorktreesDirectory(key: String, value: Any) -> Bool {
        guard key == WorkspaceDisk.worktreesDirectoryKey, let path = value as? String else { return false }
        return WorkspaceDisk.isLegacyWorktreesDirectory(path)
    }

    private static func agentUIHasQuit() -> Bool {
        var message = String(localized: "Heka takes over the projects, terminals and settings of AgentUI, which must be closed while they move.")
        while let agentUI = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { kill($0.processIdentifier, 0) == 0 }) {
            switch confirm(String(localized: "Quit AgentUI to move it into Heka?"), message,
                           action: String(localized: "Quit AgentUI"), cancel: String(localized: "Quit Heka")) {
            case true?: break
            case false?: exit(0)
            case nil: return false
            }
            agentUI.terminate()
            agentUI.activate()
            let deadline = Date.now.addingTimeInterval(15)
            while kill(agentUI.processIdentifier, 0) == 0, Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
            message = String(localized: "AgentUI is still open. If it asks to confirm quitting, answer it, then try again.")
        }
        return true
    }

    private static func confirm(_ title: String, _ message: String, action: String, cancel: String) -> Bool? {
        var response: CFOptionFlags = 0
        let status = CFUserNotificationDisplayAlert(0, kCFUserNotificationNoteAlertLevel, nil, nil, nil, title as CFString, message as CFString,
                                                    action as CFString, cancel as CFString, nil, &response)
        guard status == 0 else { return nil }
        return response & 0x3 == kCFUserNotificationDefaultResponse
    }

    private static func notify(_ title: String, _ message: String) {
        CFUserNotificationDisplayNotice(0, kCFUserNotificationCautionAlertLevel, nil, nil, nil, title as CFString, message as CFString, nil)
    }
}
