import Foundation
import Darwin

struct FileStamp: Equatable, Sendable {
    let exists: Bool
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modified: Int64
    let changed: Int64

    init(_ path: String) {
        var info = stat()
        guard fstatat(AT_FDCWD, path, &info, 0) == 0 else {
            exists = false; device = 0; inode = 0; size = 0; modified = 0; changed = 0
            return
        }
        exists = true
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        changed = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
    }
}

actor GitFilterGuard {
    typealias Listing = @Sendable (String) async throws -> Data

    static let shared = GitFilterGuard()

    private struct Snapshot {
        let stamps: [String: FileStamp]
        let configuration: [String: String]
    }

    private let list: Listing
    private var snapshots: [String: Snapshot] = [:]

    init(list: @escaping Listing = { try await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/git"), GitConfiguration.listingArguments, at: $0) }) {
        self.list = list
    }

    func configuration(at root: String) async throws -> [String: String] {
        if let snapshot = snapshots[root], snapshot.stamps.allSatisfy({ FileStamp($0.key) == $0.value }) {
            return snapshot.configuration
        }
        let started = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let entries = GitConfiguration.entries(in: try await list(root))
        let configuration = GitConfiguration.disabling(filterDrivers: GitConfiguration.untrustedFilterDrivers(in: entries))
        var files = GitConfiguration.files(in: entries, root: root)
        if let repository = GitRepository.containing(root) {
            files.formUnion([repository.commonDirectory.appendingPathComponent("config").path,
                             repository.gitDirectory.appendingPathComponent("config.worktree").path,
                             repository.gitDirectory.appendingPathComponent("HEAD").path])
        }
        let stamps = Dictionary(uniqueKeysWithValues: files.map { ($0, FileStamp($0)) })
        if stamps.values.allSatisfy({ $0.changed < started }) {
            snapshots[root] = Snapshot(stamps: stamps, configuration: configuration)
        } else {
            snapshots.removeValue(forKey: root)
        }
        return configuration
    }
}
