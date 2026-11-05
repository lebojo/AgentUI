import Foundation

actor GitRootCache {
    typealias Resolver = @Sendable (String) async throws -> String

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
        let discovered = GitRepository.containing(path)?.root.path
        if let discovered, let entry = entries[path], entry.discoveredRoot == discovered { return entry.root }
        let root = try await resolve(path)
        entries[path] = discovered.map { Entry(discoveredRoot: $0, root: root) }
        return root
    }

    @concurrent static func topLevel(at path: String) async throws -> String {
        let output = try await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/git"), ["rev-parse", "--show-toplevel"], at: path)
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
