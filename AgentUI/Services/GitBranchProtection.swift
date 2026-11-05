import Foundation

struct BranchProtectionReport: Equatable, Sendable {
    static let unreadable = BranchProtectionReport(branch: .unreadable, mergeCandidates: [])

    let branch: WorktreeBranch
    let mergeCandidates: [String]
}

enum GitBranchProtection {
    @concurrent static func report(at path: String, in repositoryPath: String, checkedOutElsewhere known: Set<String>) async -> BranchProtectionReport {
        guard let repository = GitRepository.atRoot(URL(fileURLWithPath: path)) ?? GitRepository.registeredWorktree(at: path, in: repositoryPath),
              let configuration = try? await GitFilterGuard.shared.configuration(at: repositoryPath),
              let heads = remoteHeads(of: repository, in: remoteHeadFiles(in: repository.commonDirectory, remoteNames: configuration.remotes.names))
        else { return .unreadable }
        let gitDirectory = WorkspacePath.canonical(repository.gitDirectory)
        let elsewhere = checkedOutBranches(in: repository.commonDirectory).filter { $0.key != gitDirectory }.values
        let branch = WorktreeBranch(repository.branch, defaultBranches: DefaultBranch.names(remoteHeads: heads.map(\.name)),
                                    checkedOutElsewhere: known.union(elsewhere))
        return BranchProtectionReport(branch: branch, mergeCandidates: DefaultBranch.references(remoteHeads: heads))
    }

    static func mergeCandidates(of repository: GitRepository, headFiles: [String]) -> [String]? {
        remoteHeads(of: repository, in: headFiles).map(DefaultBranch.references(remoteHeads:))
    }

    static func isDefaultBranch(_ branch: String, of remote: String, in commonDirectory: URL) -> Bool {
        let prefix = "refs/remotes/\(remote)/"
        return DefaultBranch.conventionalNames.contains(branch)
            || symbolicTarget(of: commonDirectory.appendingPathComponent(prefix + "HEAD")) == prefix + branch
    }

    static func remoteHeadFiles(in commonDirectory: URL, remoteNames: [String]) -> [String] {
        let names = Set(childNames(of: commonDirectory.appendingPathComponent("refs/remotes"))).union(remoteNames)
        return names.sorted().map { "refs/remotes/\($0)/HEAD" }
    }

    private static func remoteHeads(of repository: GitRepository, in headFiles: [String]) -> [DefaultBranch.RemoteHead]? {
        guard storesReferencesInFiles(repository) else { return nil }
        let listing = headFiles.compactMap { file in
            symbolicTarget(of: repository.commonDirectory.appendingPathComponent(file)).map { "\(file)\t\($0)" }
        }
        return DefaultBranch.remoteHeads(in: listing.joined(separator: "\n"))
    }

    private static func storesReferencesInFiles(_ repository: GitRepository) -> Bool {
        repository.branch.name != ".invalid"
            && !FileManager.default.fileExists(atPath: repository.commonDirectory.appendingPathComponent("reftable").path)
    }

    private static func checkedOutBranches(in commonDirectory: URL) -> [String: String] {
        var gitDirectories = GitRepository.linkedGitDirectories(in: commonDirectory)
        if !isBare(commonDirectory) { gitDirectories.append(commonDirectory) }
        return gitDirectories.reduce(into: [:]) { branches, gitDirectory in
            guard let branch = GitRepository.headBranch(in: gitDirectory), !branch.isDetached else { return }
            branches[WorkspacePath.canonical(gitDirectory)] = branch.name
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
        guard let text = GitRepository.smallTextFile(file), text.hasPrefix("ref: ") else { return nil }
        return String(text.dropFirst("ref: ".count))
    }
}
