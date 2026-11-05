import Foundation

actor GitRootCache {
    typealias Resolver = @Sendable (String) async throws -> String

    struct Location: Sendable {
        let root: String
        let repository: GitRepository?
    }

    static let shared = GitRootCache()

    private struct Entry {
        let discoveredRoot: String
        let root: String
    }

    private let resolve: Resolver
    private var entries: [String: Entry] = [:]

    init(resolve: @escaping Resolver = { try await GitRootCache.topLevel(at: $0) }) {
        self.resolve = resolve
    }

    func root(at path: String) async throws -> String {
        try await location(at: path).root
    }

    func location(at path: String) async throws -> Location {
        let discovered = GitRepository.containing(path)
        let discoveredRoot = discovered?.root.path
        let root: String
        if let discoveredRoot, let entry = entries[path], entry.discoveredRoot == discoveredRoot {
            root = entry.root
        } else {
            root = try await resolve(path)
            entries[path] = discoveredRoot.map { Entry(discoveredRoot: $0, root: root) }
        }
        let repository = discoveredRoot == root ? discovered : GitRepository.containing(root)
        return Location(root: root, repository: repository)
    }

    func prune(keepingPathsIn worktreePaths: [String]) {
        entries = entries.filter { path, _ in
            worktreePaths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    @concurrent static func topLevel(at path: String) async throws -> String {
        let output = try await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/git"), ["rev-parse", "--show-toplevel"], at: path)
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
