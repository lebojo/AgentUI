import Foundation

/// Local Git work is kept off the UI thread. Arguments never go through a shell.
enum GitService {
    static func run(_ arguments: [String], at path: String, timeout: TimeInterval = 90) async throws -> String {
        let data = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/git"), arguments, at: path,
                                                timeout: timeout, limit: 4_194_304, readOnly: false)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func createWorktree(project: Project, branch: String, root: URL = WorkspaceDisk.applicationDirectory, timeout: TimeInterval = 90) async throws -> Worktree {
        guard !branch.isEmpty, !branch.hasPrefix("-") else {
            throw WorkspaceError(message: "Indique un nom de branche, par exemple feature/interface.")
        }
        _ = try await run(["check-ref-format", "--branch", branch], at: project.path, timeout: 10)
        _ = try await run(["rev-parse", "--verify", "HEAD"], at: project.path, timeout: 10)
        let destination = root.appendingPathComponent("Worktrees").appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            _ = try await run(["worktree", "add", "-b", branch, destination.path, "HEAD"], at: project.path, timeout: timeout)
        } catch {
            let reason = error is CancellationError ? "Création annulée." : error.localizedDescription
            throw WorktreeCreationError(path: WorkspaceDisk.canonicalPath(destination), branch: branch, reason: reason)
        }
        return Worktree(name: branch, path: WorkspaceDisk.canonicalPath(destination), terminals: [TerminalRecord(name: "Terminal")])
    }

    static func existingWorktrees(project: Project) async throws -> [Worktree] {
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
