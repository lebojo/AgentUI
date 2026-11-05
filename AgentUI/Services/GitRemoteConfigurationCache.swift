import Foundation

actor GitRemoteConfigurationCache {
    typealias Listing = @Sendable (String) async -> Data?

    static let shared = GitRemoteConfigurationCache()
    static let arguments = ["config", "--null", "--show-scope", "--show-origin", "--get-regexp",
                            "^(\(GitRemoteConfiguration.keyPattern)|include\\.path|includeif\\..+\\.path)$"]

    private struct Snapshot {
        let stamps: [String: FileStamp]
        let configuration: GitRemoteConfiguration
    }

    private let list: Listing
    private var snapshots: [String: Snapshot] = [:]

    init(list: @escaping Listing = { try? await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/git"), GitRemoteConfigurationCache.arguments, at: $0) }) {
        self.list = list
    }

    func configuration(at root: String) async -> GitRemoteConfiguration {
        if let snapshot = snapshots[root], snapshot.stamps.allSatisfy({ FileStamp($0.key) == $0.value }) {
            return snapshot.configuration
        }
        let started = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let entries = GitConfiguration.entries(in: await list(root) ?? Data())
        let configuration = GitRemoteConfiguration(entries: entries.compactMap { entry in
            entry.value.map { (key: String(entry.key), value: String($0)) }
        })
        let stamps = Dictionary(uniqueKeysWithValues: Self.files(in: entries, root: root).map { ($0, FileStamp($0)) })
        if stamps.values.allSatisfy({ $0.changed < started }) {
            snapshots[root] = Snapshot(stamps: stamps, configuration: configuration)
        } else {
            snapshots.removeValue(forKey: root)
        }
        return configuration
    }

    private static func files(in entries: [GitConfiguration.Entry], root: String) -> Set<String> {
        var files = GitConfiguration.files(in: entries, root: root).union(globalFiles)
        if let repository = GitRepository.containing(root) {
            files.formUnion([repository.commonDirectory.appendingPathComponent("config").path,
                             repository.gitDirectory.appendingPathComponent("config.worktree").path,
                             repository.gitDirectory.appendingPathComponent("HEAD").path])
        }
        return files
    }

    private static var globalFiles: [String] {
        let environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return [environment["GIT_CONFIG_GLOBAL"] ?? home + "/.gitconfig", xdg + "/git/config"]
    }
}
