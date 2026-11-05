import Foundation

enum GitBranchProtection {
    @concurrent static func worktreeBranch(at path: String, checkedOutElsewhere known: Set<String>) async -> WorktreeBranch {
        guard let repository = GitRepository.containing(path) else { return .unreadable }
        let gitDirectory = WorkspacePath.canonical(repository.gitDirectory)
        let elsewhere = checkedOutBranches(in: repository.commonDirectory).filter { $0.key != gitDirectory }.values
        return WorktreeBranch(repository.branch, defaultBranches: defaultBranches(in: repository.commonDirectory),
                              checkedOutElsewhere: known.union(elsewhere))
    }

    static func isDefaultBranch(_ branch: String, of remote: String, in commonDirectory: URL) -> Bool {
        let prefix = "refs/remotes/\(remote)/"
        return DefaultBranch.conventionalNames.contains(branch)
            || symbolicTarget(of: commonDirectory.appendingPathComponent(prefix + "HEAD")) == prefix + branch
    }

    private static func defaultBranches(in commonDirectory: URL) -> Set<String> {
        DefaultBranch.names(remoteHeads: remoteHeads(in: commonDirectory).map(\.name))
    }

    private static func remoteHeads(in commonDirectory: URL) -> [DefaultBranch.RemoteHead] {
        let remotes = commonDirectory.appendingPathComponent("refs/remotes")
        let files = FileManager.default.enumerator(atPath: remotes.path)?.compactMap { $0 as? String } ?? []
        let listing = files.filter { $0.hasSuffix("/HEAD") }.sorted().compactMap { file in
            symbolicTarget(of: remotes.appendingPathComponent(file)).map { "refs/remotes/\(file)\t\($0)" }
        }
        return DefaultBranch.remoteHeads(in: listing.joined(separator: "\n"))
    }

    private static func checkedOutBranches(in commonDirectory: URL) -> [String: String] {
        let linked = commonDirectory.appendingPathComponent("worktrees")
        var gitDirectories = childNames(of: linked).map { linked.appendingPathComponent($0) }
        if !isBare(commonDirectory) { gitDirectories.append(commonDirectory) }
        return gitDirectories.reduce(into: [:]) { branches, gitDirectory in
            guard let reference = symbolicTarget(of: gitDirectory.appendingPathComponent("HEAD")),
                  reference.hasPrefix("refs/heads/") else { return }
            branches[WorkspacePath.canonical(gitDirectory)] = String(reference.dropFirst("refs/heads/".count))
        }
    }

    private static func isBare(_ commonDirectory: URL) -> Bool {
        guard let value = WorktreeFolder.coreSetting("bare", in: commonDirectory)?.lowercased() else {
            return commonDirectory.lastPathComponent != ".git"
        }
        return ["true", "yes", "on", "1"].contains(value)
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
