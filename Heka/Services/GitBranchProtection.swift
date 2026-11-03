import Foundation

struct BranchProtectionReport: Equatable, Sendable {
    static let unreadable = BranchProtectionReport(branch: .unreadable, mergeCandidates: [])

    let branch: WorktreeBranch
    let mergeCandidates: [String]
}

enum GitBranchProtection {
    @concurrent static func report(at path: String, in repositoryPath: String) async -> BranchProtectionReport {
        guard let repository = GitRepository.atRoot(URL(fileURLWithPath: path)) ?? GitRepository.registeredWorktree(at: path, in: repositoryPath),
              let configuration = try? await GitFilterGuard.shared.configuration(at: repositoryPath),
              let heads = remoteHeads(of: repository, in: remoteHeadFiles(in: repository.commonDirectory, remoteNames: configuration.remotes.names))
        else { return .unreadable }
        let gitDirectory = WorkspacePath.canonical(repository.gitDirectory)
        let elsewhere = checkedOutBranches(in: repository.commonDirectory, isBare: configuration.isBare).filter { $0.key != gitDirectory }.values.joined()
        let branch = WorktreeBranch(repository.branch, defaultBranches: DefaultBranch.names(remoteHeads: heads.map(\.name)),
                                    checkedOutElsewhere: Set(elsewhere))
        return BranchProtectionReport(branch: branch, mergeCandidates: DefaultBranch.references(remoteHeads: heads))
    }

    static func isCheckedOut(_ branch: String, inRepositoryAt path: String) async -> Bool {
        guard let repository = GitRepository.containing(path) else { return false }
        let isBare = (try? await GitFilterGuard.shared.configuration(at: path))?.isBare ?? false
        return checkedOutBranches(in: repository.commonDirectory, isBare: isBare).values.contains { $0.contains(branch) }
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
        return headFiles.compactMap { file in
            symbolicTarget(of: repository.commonDirectory.appendingPathComponent(file)).flatMap { DefaultBranch.RemoteHead(headFile: file, target: $0) }
        }
    }

    private static func storesReferencesInFiles(_ repository: GitRepository) -> Bool {
        repository.branch.name != ".invalid"
            && !FileManager.default.fileExists(atPath: repository.commonDirectory.appendingPathComponent("reftable").path)
    }

    private static func checkedOutBranches(in commonDirectory: URL, isBare: Bool) -> [String: Set<String>] {
        var gitDirectories = GitRepository.linkedGitDirectories(in: commonDirectory)
        if !isBare { gitDirectories.append(commonDirectory) }
        return gitDirectories.reduce(into: [:]) { branches, gitDirectory in
            let names = branchesInUse(in: gitDirectory)
            if !names.isEmpty { branches[WorkspacePath.canonical(gitDirectory)] = names }
        }
    }

    private static func branchesInUse(in gitDirectory: URL) -> Set<String> {
        let rebased = ["rebase-merge/head-name", "rebase-apply/head-name"].compactMap { file in
            GitRepository.smallTextFile(gitDirectory.appendingPathComponent(file)).flatMap(localBranchName(of:))
        }
        let bisected = GitRepository.smallTextFile(gitDirectory.appendingPathComponent("BISECT_START")).flatMap { $0.isEmpty ? nil : $0 }
        let head = GitRepository.headBranch(in: gitDirectory).flatMap { $0.isDetached ? nil : $0.name }
        return Set(rebased + [bisected, head].compactMap { $0 })
    }

    private static func localBranchName(of reference: String) -> String? {
        let prefix = "refs/heads/"
        guard reference.hasPrefix(prefix), reference.count > prefix.count else { return nil }
        return String(reference.dropFirst(prefix.count))
    }

    private static func childNames(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private static func symbolicTarget(of file: URL) -> String? {
        guard let text = GitRepository.smallTextFile(file), text.hasPrefix("ref: ") else { return nil }
        return String(text.dropFirst("ref: ".count))
    }
}
