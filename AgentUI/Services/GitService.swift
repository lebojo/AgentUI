import Foundation

enum GitService {
    @concurrent static func run(_ arguments: [String], at path: String, timeout: TimeInterval = 90) async throws -> String {
        let data = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/git"), arguments, at: path,
                                                timeout: timeout, limit: 4_194_304, readOnly: false)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @concurrent static func createWorktree(project: Project, branch: String, root: URL = WorkspaceDisk.worktreesDirectory, timeout: TimeInterval = 90) async throws -> Worktree {
        guard !branch.isEmpty, !branch.hasPrefix("-") else {
            throw WorkspaceError(message: "Indique un nom de branche, par exemple feature/interface.")
        }
        _ = try await run(["check-ref-format", "--branch", branch], at: project.path, timeout: 10)
        let source = try await branchSource(branch, at: project.path)
        if source == .checkedOut {
            throw WorkspaceError(message: "La branche « \(branch) » est déjà utilisée par un autre worktree ou par le dossier du projet.")
        }
        if source == .new { _ = try await run(["rev-parse", "--verify", "HEAD"], at: project.path, timeout: 10) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = availableDestination(in: root, name: "\(project.name)-\(branch.replacingOccurrences(of: "/", with: "-"))")
        do {
            let arguments = source == .new ? ["worktree", "add", "-b", branch, destination.path, "HEAD"] : ["worktree", "add", destination.path, branch]
            _ = try await run(arguments, at: project.path, timeout: timeout)
        } catch {
            let reason = error is CancellationError ? "Création annulée." : error.localizedDescription
            throw WorktreeCreationError(path: WorkspaceDisk.canonicalPath(destination), branch: branch, reason: reason)
        }
        return Worktree(name: branch, path: WorkspaceDisk.canonicalPath(destination), terminals: [TerminalRecord(name: "Terminal")])
    }

    @concurrent static func removeWorktree(project: Project, path: String, timeout: TimeInterval = 90) async throws {
        guard WorkspaceDisk.canonicalPath(URL(fileURLWithPath: path)) != project.path else {
            throw WorkspaceError(message: "Le dossier principal du projet ne peut pas être supprimé.")
        }
        if FileManager.default.fileExists(atPath: path) {
            _ = try await run(["worktree", "remove", "--force", path], at: project.path, timeout: timeout)
        } else {
            _ = try await run(["worktree", "prune"], at: project.path, timeout: 10)
        }
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

    @concurrent static func existingWorktrees(project: Project) async throws -> [Worktree] {
        let output = try await run(["worktree", "list", "--porcelain", "-z"], at: project.path, timeout: 10)
        var result: [Worktree] = []
        var path: String?
        var branch: String?
        func append() {
            if let path, path != project.path {
                result.append(Worktree(name: branch ?? URL(fileURLWithPath: path).lastPathComponent,
                                      path: path, terminals: [TerminalRecord(name: "Terminal")]))
            }
        }
        for field in output.components(separatedBy: "\0") {
            if field.hasPrefix("worktree ") {
                append()
                path = WorkspaceDisk.canonicalPath(URL(fileURLWithPath: String(field.dropFirst(9))))
                branch = nil
            } else if field.hasPrefix("branch refs/heads/") {
                branch = String(field.dropFirst(18))
            }
        }
        append()
        return result
    }
}

struct WorktreeCreationError: LocalizedError {
    let path: String
    let branch: String
    let reason: String
    var errorDescription: String? {
        "\(reason) La création peut être partielle. Les fichiers existants sont conservés. Vérifie la branche « \(branch) » et le dossier \(path) avant de réessayer."
    }
}
