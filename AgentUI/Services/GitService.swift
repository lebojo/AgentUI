import Foundation

enum GitService {
    @concurrent static func run(_ arguments: [String], at path: String, timeout: TimeInterval = 90,
                                overflow: CommandRunner.OutputOverflow = .stop) async throws -> String {
        let data = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/git"), arguments, at: path,
                                                timeout: timeout, limit: 4_194_304, readOnly: false, overflow: overflow)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @concurrent static func createWorktree(project: Project, branch: String, remote: String? = nil, root: URL = WorkspaceDisk.worktreesDirectory, timeout: TimeInterval = 90) async throws -> Worktree {
        guard !branch.isEmpty, !branch.hasPrefix("-") else {
            throw WorkspaceError(message: String(localized: "Enter a branch name, for example feature/interface."))
        }
        _ = try await run(["check-ref-format", "--branch", branch], at: project.path, timeout: 10)
        let source = try await branchSource(branch, at: project.path)
        if source == .checkedOut {
            throw WorkspaceError(message: String(localized: "The branch “\(branch)” is already used by another worktree or by the project folder."))
        }
        if source == .new { _ = try await run(["rev-parse", "--verify", "HEAD"], at: project.path, timeout: 10) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = availableDestination(in: root, name: "\(project.name)-\(branch.replacingOccurrences(of: "/", with: "-"))")
        do {
            let arguments = switch (source, remote) {
            case (.new, _): ["worktree", "add", "-b", branch, destination.path, "HEAD"]
            case (.remote, let remote?): ["worktree", "add", "--track", "-b", branch, destination.path, "\(remote)/\(branch)"]
            default: ["worktree", "add", destination.path, branch]
            }
            _ = try await run(arguments, at: project.path, timeout: timeout)
        } catch {
            let reason = error is CancellationError ? String(localized: "Creation cancelled.") : error.localizedDescription
            throw WorktreeCreationError(path: WorkspacePath.canonical(destination), branch: branch, reason: reason)
        }
        return Worktree(name: branch, path: WorkspacePath.canonical(destination), terminals: [TerminalRecord(name: "Terminal")])
    }

    @concurrent static func removeWorktree(project: Project, path: String, timeout: TimeInterval = 90) async throws {
        guard WorkspacePath.canonical(URL(fileURLWithPath: path)) != project.path else {
            throw WorkspaceError(message: String(localized: "The project’s main folder can’t be deleted."))
        }
        if FileManager.default.fileExists(atPath: path) {
            _ = try await run(["worktree", "remove", "--force", path], at: project.path, timeout: timeout)
        } else {
            _ = try await run(["worktree", "prune"], at: project.path, timeout: 10)
        }
    }

    @concurrent static func worktreeBranch(at path: String, project: Project) async -> WorktreeBranch {
        async let head = run(["rev-parse", "--symbolic-full-name", "HEAD"], at: path, timeout: 10)
        async let worktrees = run(["worktree", "list", "--porcelain", "-z"], at: project.path, timeout: 10)
        async let heads = remoteHeads(at: project.path)
        do {
            let reference = try await head
            let branch = reference.hasPrefix("refs/heads/") ? GitBranch(name: String(reference.dropFirst("refs/heads/".count))) : nil
            return WorktreeBranch(branch, defaultBranches: DefaultBranch.names(remoteHeads: try await heads.map(\.name)),
                                  checkedOutElsewhere: checkedOutBranches(in: try await worktrees, excluding: path))
        } catch {
            return .unreadable
        }
    }

    private static func remoteHeads(at path: String) async throws -> [DefaultBranch.RemoteHead] {
        DefaultBranch.remoteHeads(in: try await run(["for-each-ref", "--format=%(refname)%09%(symref)", "refs/remotes/*/HEAD"], at: path, timeout: 10))
    }

    private static func checkedOutBranches(in porcelain: String, excluding path: String) -> Set<String> {
        let own = WorkspacePath.canonical(URL(fileURLWithPath: path))
        return Set(worktreeEntries(in: porcelain).filter { $0.path != own }.compactMap(\.branch))
    }

    static func worktreeEntries(in porcelain: String) -> [GitWorktreeEntry] {
        var entries: [GitWorktreeEntry] = []
        for field in porcelain.split(separator: "\0") {
            if field.hasPrefix("worktree ") {
                entries.append(GitWorktreeEntry(path: WorkspacePath.canonical(URL(fileURLWithPath: String(field.dropFirst("worktree ".count))))))
            } else if field.hasPrefix("branch refs/heads/"), !entries.isEmpty {
                entries[entries.count - 1].branch = String(field.dropFirst("branch refs/heads/".count))
            }
        }
        return entries
    }

    @concurrent static func deleteBranch(_ branch: String, _ removal: BranchRemoval, project: Project) async throws {
        guard let arguments = removal.arguments(for: branch) else { return }
        if removal.requiresMerge { try await requireMergedIntoDefaultBranch(branch, at: project.path) }
        _ = try await run(arguments, at: project.path, timeout: 20)
    }

    private static func requireMergedIntoDefaultBranch(_ branch: String, at path: String) async throws {
        let targets = try await defaultBranchReferences(at: path)
        guard !targets.isEmpty else {
            throw WorkspaceError(message: String(localized: "The repository’s main branch couldn’t be found, so the branch “\(branch)” wasn’t deleted. If its commits are no longer needed, delete it with git branch -D \(branch)."))
        }
        let reference = "refs/heads/" + branch
        let merged = try await run(["for-each-ref", "--format=%(refname)"] + targets.map { "--merged=" + $0 } + [reference], at: path, timeout: 20)
        guard merged.split(whereSeparator: \.isNewline).contains(where: { $0 == reference }) else {
            throw WorkspaceError(message: String(localized: "The branch “\(branch)” isn’t fully merged. If its commits are no longer needed, delete it with git branch -D \(branch)."))
        }
    }

    private static func defaultBranchReferences(at path: String) async throws -> [String] {
        let heads = try await remoteHeads(at: path)
        let candidates = DefaultBranch.references(remoteHeads: heads)
        let output = try await run(["for-each-ref", "--format=%(refname)%09%(upstream)%09%(upstream:track)"] + candidates, at: path, timeout: 10)
        return DefaultBranch.mergeTargets(in: output, candidates: candidates)
    }

    static func hasLocalChanges(at path: String) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return try await !run(["status", "--porcelain", "--untracked-files=normal"], at: path, timeout: 20).isEmpty
    }

    private enum BranchSource {
        case new, local, remote, checkedOut
    }

    private static func branchSource(_ branch: String, at path: String) async throws -> BranchSource {
        let local = try await run(["branch", "--list", branch], at: path, timeout: 10)
        if let marker = local.first { return marker == "*" || marker == "+" ? .checkedOut : .local }
        let remote = try await run(["branch", "--remotes", "--list", "*/" + branch], at: path, timeout: 10)
        return remote.isEmpty ? .new : .remote
    }

    private static func availableDestination(in root: URL, name: String) -> URL {
        var destination = root.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = root.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return destination
    }

    @concurrent static func availableBranches(project: Project) async throws -> [BranchSuggestion] {
        let output = try await run(["for-each-ref", "--sort=-committerdate", "--format=%(refname)\t%(worktreepath)", "refs/heads", "refs/remotes"],
                                   at: project.path, timeout: 10)
        let remotes = try await run(["remote"], at: project.path, timeout: 10).split(whereSeparator: \.isNewline).map(String.init)
        return branchSuggestions(from: output, remotes: remotes)
    }

    @concurrent static func fetchRemotes(project: Project) async throws {
        _ = try await run(["fetch", "--all", "--quiet"], at: project.path, timeout: 30)
    }

    static func branchSuggestions(from output: String, remotes: [String]) -> [BranchSuggestion] {
        let localPrefix = "refs/heads/", remotePrefix = "refs/remotes/"
        let remotesByLength = remotes.sorted { $0.count > $1.count }
        let references = output.split(whereSeparator: \.isNewline).map { line in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return (name: String(fields[0]), worktree: fields.count > 1 ? String(fields[1]) : "")
        }
        var known = Set(references.compactMap { $0.name.hasPrefix(localPrefix) ? String($0.name.dropFirst(localPrefix.count)) : nil })
        var suggestions: [BranchSuggestion] = []
        for reference in references {
            if reference.name.hasPrefix(localPrefix) {
                guard reference.worktree.isEmpty else { continue }
                suggestions.append(BranchSuggestion(name: String(reference.name.dropFirst(localPrefix.count)), origin: .local))
            } else if reference.name.hasPrefix(remotePrefix) {
                let path = reference.name.dropFirst(remotePrefix.count)
                guard let remote = remotesByLength.first(where: { path.hasPrefix($0 + "/") }) else { continue }
                let name = String(path.dropFirst(remote.count + 1))
                guard !name.isEmpty, name != "HEAD", known.insert(name).inserted else { continue }
                suggestions.append(BranchSuggestion(name: name, origin: .remote(remote)))
            }
        }
        return suggestions
    }

    @concurrent static func existingWorktrees(project: Project) async throws -> [Worktree] {
        let output = try await run(["worktree", "list", "--porcelain", "-z"], at: project.path, timeout: 10)
        return worktreeEntries(in: output).filter { $0.path != project.path }.map { entry in
            Worktree(name: entry.branch ?? URL(fileURLWithPath: entry.path).lastPathComponent, path: entry.path,
                     terminals: [TerminalRecord(name: "Terminal")])
        }
    }
}

struct GitWorktreeEntry: Equatable, Sendable {
    let path: String
    var branch: String?
}

struct WorktreeCreationError: LocalizedError {
    let path: String
    let branch: String
    let reason: String
    var errorDescription: String? {
        String(localized: "\(reason) Creation may be partial. Existing files are kept. Check the branch “\(branch)” and the folder \(path) before trying again.")
    }
}
