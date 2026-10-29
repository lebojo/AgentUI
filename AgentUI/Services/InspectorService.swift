import Foundation

enum InspectorService {
    @concurrent static func children(at url: URL) async throws -> [ExplorerEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))
            .filter { $0.lastPathComponent != ".git" && $0.lastPathComponent != ".DS_Store" }
            .map { url in
                let values = try url.resourceValues(forKeys: keys)
                return ExplorerEntry(url: url, isDirectory: values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true,
                                     isSymbolicLink: values.isSymbolicLink == true)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    static func textFile(_ url: URL) async throws -> String {
        let content = try await textContent(url)
        return content.text + (content.isTruncated ? "\n\n[Aperçu limité à 128 Ko]" : "")
    }

    @concurrent static func textContent(_ url: URL) async throws -> TextContent {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ReadCommandError(message: "Ce fichier ne peut pas être prévisualisé. Utilise le Finder pour l’ouvrir.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 131_073) ?? Data()
        var prefix = Data(data.prefix(131_072))
        if data.count > 131_072 {
            var start = prefix.count - 1
            while start > 0 && prefix[start] & 0xC0 == 0x80 { start -= 1 }
            let lead = prefix[start]
            let width = lead >= 0xF0 && lead <= 0xF4 ? 4 : (lead >= 0xE0 && lead <= 0xEF ? 3 : (lead >= 0xC2 && lead <= 0xDF ? 2 : 1))
            if prefix.count - start < width { prefix.removeSubrange(start...) }
        }
        guard !data.contains(0), let text = String(data: prefix, encoding: .utf8) else {
            throw ReadCommandError(message: "Ce fichier n’est pas un texte UTF-8. Ouvre-le dans son application.")
        }
        return TextContent(text: text, isTruncated: data.count > 131_072)
    }

    @concurrent static func localGit(at path: String) async throws -> LocalGitSnapshot {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let rootData = try await ReadCommand.run(git, ["rev-parse", "--show-toplevel"], at: path)
        let root = String(decoding: rootData, as: UTF8.self).trimmingCharacters(in: .newlines)
        async let head = try? ReadCommand.run(git, ["rev-parse", "--verify", "HEAD"], at: root)
        let safety = try await worktreeReadConfiguration(git, at: root)
        async let changes = ReadCommand.run(git, ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=dirty"],
                                            at: root, gitConfiguration: safety)
        let branch = GitRepository.containing(root)?.branch
        return LocalGitSnapshot(root: root, branch: branch,
                                headSHA: await head.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines) },
                                changes: GitChange.parsePorcelain(try await changes))
    }

    @concurrent static func diff(_ change: GitChange, at root: String) async throws -> GitDiff {
        if change.isUntracked {
            let url = URL(fileURLWithPath: root).appendingPathComponent(change.path)
            let content = try await textContent(url)
            let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
            return GitDiff(path: change.path, sections: [.untracked(path: change.path, content: content, isExecutable: isExecutable)])
        }
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let paths = [change.path] + (change.originalPath.map { [$0] } ?? [])
        let flags = ["--literal-pathspecs", "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=dirty"]
        let safety = try await worktreeReadConfiguration(git, at: root)
        async let staged = section(git, flags + ["--cached", "--"] + paths, at: root, kind: .staged, safety: safety)
        async let unstaged = section(git, flags + ["--"] + paths, at: root, kind: .unstaged, safety: safety)
        return GitDiff(path: change.path, sections: try await [staged, unstaged].compactMap { $0 })
    }

    @concurrent private static func section(_ git: URL, _ arguments: [String], at root: String, kind: GitDiffSection.Kind,
                                            safety: [String: String]) async throws -> GitDiffSection? {
        let patch = String(decoding: try await ReadCommand.run(git, arguments, at: root, limit: 524_288, gitConfiguration: safety), as: UTF8.self)
        return patch.isEmpty ? nil : GitDiffSection(kind: kind, patch: patch)
    }

    private static func worktreeReadConfiguration(_ git: URL, at root: String) async throws -> [String: String] {
        let listing = try await ReadCommand.run(git, GitConfiguration.listingArguments, at: root)
        return GitConfiguration.disabling(filterDrivers: GitConfiguration.untrustedFilterDrivers(in: listing))
    }

    @concurrent static func github(at path: String, branch: GitBranch?, headSHA: String?, executable override: URL? = nil) async throws -> GitHubSnapshot {
        guard let gh = override ?? ReadCommand.executable("gh") else {
            throw ReadCommandError(message: "GitHub CLI n’est pas installé. Installe gh, puis lance gh auth login dans un terminal.")
        }
        let decoder = JSONDecoder()
        let repoData = try await ReadCommand.run(gh, ["repo", "view", "--json", "nameWithOwner,url,description"], at: path)
        let repository = try decoder.decode(GitHubRepository.self, from: repoData)
        var pr: GitHubPullRequest?
        var prError: String?
        if let branch, !branch.isDetached {
            do {
                let data = try await ReadCommand.run(gh, ["pr", "view", branch.name, "--repo", repository.url,
                    "--json", "number,title,url,state,isDraft,headRefName,headRefOid,baseRefName,reviewDecision,statusCheckRollup"], at: path)
                pr = try decoder.decode(GitHubPullRequest.self, from: data)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if !error.localizedDescription.lowercased().contains("no pull requests found") {
                    prError = error.localizedDescription
                }
            }
        }
        var runs: [GitHubRun] = []
        var checksError: String?
        if let headSHA {
            do {
                let data = try await ReadCommand.run(gh, ["run", "list", "--repo", repository.url, "--commit", headSHA, "--limit", "10",
                    "--json", "databaseId,displayTitle,workflowName,status,conclusion,headSha,url"], at: path)
                runs = try decoder.decode([GitHubRun].self, from: data)
            } catch is CancellationError { throw CancellationError() }
            catch { checksError = error.localizedDescription }
        }
        return GitHubSnapshot(repository: repository, pullRequest: pr, runs: runs, pullRequestError: prError, checksError: checksError)
    }
}
