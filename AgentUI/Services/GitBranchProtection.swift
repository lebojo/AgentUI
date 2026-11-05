import Foundation

struct ProtectedBranches: Equatable, Sendable {
    static let conventional = ProtectedBranches(defaults: DefaultBranch.names(remoteHeads: []), checkedOutElsewhere: [])

    let defaults: Set<String>
    let checkedOutElsewhere: Set<String>
}

enum GitBranchProtection {
    struct Repository: Sendable {
        let defaults: Set<String>
        let checkedOut: [String: String]

        func protectedBranches(forGitDirectory gitDirectory: String) -> ProtectedBranches {
            ProtectedBranches(defaults: defaults, checkedOutElsewhere: Set(checkedOut.filter { $0.key != gitDirectory }.values))
        }
    }

    static func read(commonDirectory: URL) -> Repository {
        Repository(defaults: DefaultBranch.names(remoteHeads: remoteHeads(in: commonDirectory).map(\.name)),
                   checkedOut: checkedOutBranches(in: commonDirectory))
    }

    static func remoteHeads(in commonDirectory: URL) -> [DefaultBranch.RemoteHead] {
        let remotes = commonDirectory.appendingPathComponent("refs/remotes")
        let listing = childNames(of: remotes).compactMap { name in
            symbolicTarget(of: remotes.appendingPathComponent(name).appendingPathComponent("HEAD"))
                .map { "refs/remotes/\(name)/HEAD\t\($0)" }
        }
        return DefaultBranch.remoteHeads(in: listing.joined(separator: "\n"))
    }

    static func checkedOutBranches(in commonDirectory: URL) -> [String: String] {
        let linked = commonDirectory.appendingPathComponent("worktrees")
        var gitDirectories = childNames(of: linked).map { linked.appendingPathComponent($0) }
        if commonDirectory.lastPathComponent == ".git" { gitDirectories.append(commonDirectory) }
        return gitDirectories.reduce(into: [:]) { branches, gitDirectory in
            guard let reference = symbolicTarget(of: gitDirectory.appendingPathComponent("HEAD")),
                  reference.hasPrefix("refs/heads/") else { return }
            branches[WorkspacePath.canonical(gitDirectory)] = String(reference.dropFirst("refs/heads/".count))
        }
    }

    private static func childNames(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private static func symbolicTarget(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("ref: ") else { return nil }
        return String(text.dropFirst("ref: ".count))
    }
}
