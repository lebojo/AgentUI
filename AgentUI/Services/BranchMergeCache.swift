import Foundation

actor BranchMergeCache {
    typealias Targets = @Sendable ([String], String) async throws -> [String]
    typealias Merged = @Sendable (String, [String], String) async throws -> Bool

    static let shared = BranchMergeCache()

    private struct Key: Equatable {
        let branch: String
        let headSHA: String
    }

    private struct Entry {
        let key: Key
        let stamps: [String: FileStamp]
        let state: BranchMergeState
    }

    private let targets: Targets
    private let merged: Merged
    private var entries: [String: Entry] = [:]

    init(targets: @escaping Targets = { try await GitService.mergeTargets(among: $0, at: $1) },
         merged: @escaping Merged = { try await GitService.isMerged($0, into: $1, at: $2) }) {
        self.targets = targets
        self.merged = merged
    }

    func state(of branch: String, headSHA: String, in repository: GitRepository, at root: String, remoteNames: [String]) async -> BranchMergeState {
        let key = Key(branch: branch, headSHA: headSHA)
        if let entry = entries[root], entry.key == key, entry.stamps.allSatisfy({ FileStamp($0.key) == $0.value }) {
            return entry.state
        }
        let common = repository.commonDirectory
        let headFiles = GitBranchProtection.remoteHeadFiles(in: common, remoteNames: remoteNames)
        guard let candidates = GitBranchProtection.mergeCandidates(of: repository, headFiles: headFiles) else {
            entries.removeValue(forKey: root)
            return .unknown
        }
        let sources = ["config", "packed-refs", "reftable", "refs/remotes"] + headFiles
        var stamps = Self.stamps(of: sources + candidates, in: common)
        do {
            let found = try await targets(candidates, root)
            guard !found.isEmpty else { return remember(.unknown, for: key, stamps: stamps, at: root) }
            stamps.merge(Self.stamps(of: found, in: common)) { old, _ in old }
            let state: BranchMergeState = try await merged(branch, found, root) ? .merged : .unmerged
            return remember(state, for: key, stamps: stamps, at: root)
        } catch {
            entries.removeValue(forKey: root)
            return .unknown
        }
    }

    private func remember(_ state: BranchMergeState, for key: Key, stamps: [String: FileStamp], at root: String) -> BranchMergeState {
        entries[root] = Entry(key: key, stamps: stamps, state: state)
        return state
    }

    private static func stamps(of files: [String], in commonDirectory: URL) -> [String: FileStamp] {
        Dictionary(files.map { commonDirectory.appendingPathComponent($0).path }.map { ($0, FileStamp($0)) }) { first, _ in first }
    }
}
