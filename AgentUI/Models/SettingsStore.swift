import Foundation
import Observation

@MainActor @Observable final class SettingsStore {
    private enum Key {
        static let terminal = "settings.terminal"
        static let agentLaunch = "settings.agentLaunch"
        static let confirmations = "settings.confirmations"
    }

    var terminal: TerminalAppearance {
        didSet { if oldValue != terminal { save(terminal, forKey: Key.terminal) } }
    }
    var agentLaunch: AgentLaunch {
        didSet { if oldValue != agentLaunch { save(agentLaunch, forKey: Key.agentLaunch) } }
    }
    var confirmations: RemovalConfirmations {
        didSet { if oldValue != confirmations { save(confirmations, forKey: Key.confirmations) } }
    }
    var worktreesDirectory: URL {
        didSet { if oldValue != worktreesDirectory { saveWorktreesDirectory() } }
    }
    var usesDefaultWorktreesDirectory: Bool { worktreesDirectory.path == WorkspaceDisk.defaultWorktreesDirectory.path }
    var creationWorktreesDirectory: URL { WorkspaceDisk.testWorktreesDirectory ?? worktreesDirectory }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminal = Self.load(TerminalAppearance.self, forKey: Key.terminal, from: defaults) ?? TerminalAppearance()
        agentLaunch = Self.load(AgentLaunch.self, forKey: Key.agentLaunch, from: defaults) ?? AgentLaunch()
        confirmations = Self.load(RemovalConfirmations.self, forKey: Key.confirmations, from: defaults) ?? RemovalConfirmations()
        worktreesDirectory = WorkspaceDisk.storedWorktreesDirectory(in: defaults)
    }

    private func saveWorktreesDirectory() {
        if usesDefaultWorktreesDirectory { defaults.removeObject(forKey: WorkspaceDisk.worktreesDirectoryKey) }
        else { defaults.set(worktreesDirectory.path, forKey: WorkspaceDisk.worktreesDirectoryKey) }
    }

    private func save(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String, from defaults: UserDefaults) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
