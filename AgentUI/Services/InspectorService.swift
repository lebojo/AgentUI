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
        return content.text + (content.isTruncated ? "\n\n[" + String(localized: "Preview limited to 128 KB") + "]" : "")
    }

    @concurrent static func textContent(_ url: URL) async throws -> TextContent {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ReadCommandError(message: String(localized: "This file can’t be previewed. Use the Finder to open it.")) }
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
            throw ReadCommandError(message: String(localized: "This file isn’t UTF-8 text. Open it in its app."))
        }
        return TextContent(text: text, isTruncated: data.count > 131_072)
    }

    @concurrent static func localGit(at path: String, changesIn paths: [String]? = nil) async throws -> LocalGitSnapshot {
        let root = try await root(at: path)
        let configuration = try await GitFilterGuard.shared.configuration(at: root)
        let status = try await status(at: root, paths: paths, configuration: configuration)
        let repository = GitRepository.containing(root)
        let branch = repository?.branch
        let remotes = configuration.remotes
        let publishedBranch = branch.flatMap { $0.isDetached ? nil : $0.name }
        var tracking = status.tracking
        if let publishedBranch, tracking != nil {
            tracking?.tracksSameBranch = remotes.tracksSameBranch(publishedBranch)
            if tracking?.upstream != nil, tracking?.tracksSameBranch == false, let upstream = remotes.upstream(of: publishedBranch),
               let repository, !GitBranchProtection.isDefaultBranch(upstream.branch, of: upstream.remote, in: repository.commonDirectory) {
                tracking?.namedUpstream = upstream
            }
            if tracking?.isPublished == false { tracking?.remote = remotes.pushRemote(for: publishedBranch) }
            if tracking?.goneUpstream != nil { tracking?.hasUnmergedWork = await GitService.hasWorkOutsideDefaultBranch(publishedBranch, at: root) }
        }
        let pushRemoteURL = tracking?.namedUpstream.flatMap { remotes.url(ofRemote: $0.remote) } ?? publishedBranch.flatMap(remotes.pushURL(for:))
        let shown = Array(status.changes.prefix(LocalGitSnapshot.changeLimit))
        return LocalGitSnapshot(root: root, branch: branch, headSHA: status.headSHA, changes: shown,
                                omittedChanges: status.changes.count - shown.count + (status.isTruncated ? 1 : 0),
                                isTruncated: status.isTruncated ? true : nil, tracking: tracking,
                                webAddress: remotes.primaryURL.flatMap(RemoteWebAddress.init(remoteURL:)),
                                pushWebAddress: pushRemoteURL.flatMap(RemoteWebAddress.init(remoteURL:)))
    }

    @concurrent private static func status(at root: String, paths: [String]?, configuration: GitFilterGuard.Configuration) async throws -> GitStatus {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        guard paths?.isEmpty != true else {
            let head = try? await ReadCommand.run(git, ["rev-parse", "--verify", "HEAD"], at: root)
            return GitStatus(headSHA: head.map(trimmed))
        }
        let arguments = GitStatus.arguments + (paths.map { ["--"] + $0 } ?? [])
        let output = try await ReadCommand.run(git, arguments, at: root, limit: GitStatus.outputLimit, overflow: .truncate,
                                               gitConfiguration: configuration.overrides)
        return GitStatus.parse(output, isTruncated: output.count >= GitStatus.outputLimit)
    }

    @concurrent static func perform(_ action: GitAction, at root: String) async throws {
        _ = try await GitService.run(action.arguments, at: root, timeout: action.timeout, overflow: .discard)
    }

    @concurrent static func diff(_ change: GitChange, at root: String,
                                 including kinds: Set<GitDiffSection.Kind> = [.staged, .unstaged]) async throws -> GitDiff {
        if change.isUntracked {
            let url = URL(fileURLWithPath: root).appendingPathComponent(change.path)
            let content = try await textContent(url)
            let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
            return GitDiff(path: change.path, sections: [.untracked(path: change.path, content: content, isExecutable: isExecutable)])
        }
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let paths = [change.path] + (change.originalPath.map { [$0] } ?? [])
        let safety = try await GitFilterGuard.shared.configuration(at: root).overrides
        async let staged = kinds.contains(.staged) ? section(git, diffFlags + ["--cached", "--"] + paths, at: root, kind: .staged, safety: safety) : nil
        async let unstaged = kinds.contains(.unstaged) ? section(git, diffFlags + ["--"] + paths, at: root, kind: .unstaged, safety: safety) : nil
        return GitDiff(path: change.path, sections: try await [staged, unstaged].compactMap { $0 })
    }

    static func root(at path: String) async throws -> String {
        try await GitRootCache.shared.root(at: path)
    }

    @concurrent static func branches(at root: String, limit: Int = 200) async throws -> GitBranchList {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let refs = String(decoding: try await ReadCommand.run(git, ["for-each-ref", "--sort=-committerdate", "--format=%(refname)%09%(symref)",
                                                                    "refs/heads", "refs/remotes"], at: root), as: UTF8.self)
        let branch = GitRepository.containing(root)?.branch
        let current = branch.flatMap { $0.isDetached ? nil : "refs/heads/" + $0.name }
        let all = refs.split(separator: "\n").compactMap { line -> ComparisonBranch? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[1].isEmpty, String(fields[0]) != current else { return nil }
            return ComparisonBranch(reference: String(fields[0]))
        }
        let candidates = DefaultBranch.references(remoteHeads: DefaultBranch.remoteHeads(in: refs))
        let preferred = candidates.lazy.compactMap { candidate in all.first { $0.reference == candidate } }.first
        var shown = Array(all.prefix(limit))
        if let preferred, !shown.contains(preferred) { shown.insert(preferred, at: 0) }
        return GitBranchList(branches: shown, defaultBranch: preferred, omitted: all.count - shown.count)
    }

    @concurrent static func comparison(with base: ComparisonBranch, at root: String) async throws -> BranchComparison {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        try validate(base)
        async let changes = comparedChanges(with: base, at: root)
        async let commits = ReadCommand.run(git, ["rev-list", "--count", base.reference + "..HEAD", "--"], at: root)
        let all = try await changes
        let shown = Array(all.prefix(LocalGitSnapshot.changeLimit))
        return BranchComparison(base: base, commits: Int(trimmed(try await commits)) ?? 0, changes: shown, omittedChanges: all.count - shown.count)
    }

    @concurrent static func comparedChanges(with base: ComparisonBranch, at root: String, paths: [String]? = nil) async throws -> [GitChange] {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        try validate(base)
        let safety = try await GitFilterGuard.shared.configuration(at: root).overrides
        let arguments = diffFlags + ["--name-status", "-z", "--find-renames", base.reference + "...HEAD", "--"] + (paths ?? [])
        return GitChange.parseNameStatus(try await ReadCommand.run(git, arguments, at: root, gitConfiguration: safety))
    }

    @concurrent static func comparisonDiff(_ change: GitChange, base: ComparisonBranch, at root: String) async throws -> GitDiff {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        try validate(base)
        let paths = [change.path] + (change.originalPath.map { [$0] } ?? [])
        let arguments = diffFlags + ["--find-renames", base.reference + "...HEAD", "--"] + paths
        let safety = try await GitFilterGuard.shared.configuration(at: root).overrides
        let section = try await section(git, arguments, at: root, kind: .committed, safety: safety)
        return GitDiff(path: change.path, sections: [section].compactMap { $0 })
    }

    private static let diffFlags = ["--literal-pathspecs", "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=dirty"]

    private static func validate(_ base: ComparisonBranch) throws {
        guard base.isBranchReference else { throw ReadCommandError(message: String(localized: "Choose a branch to compare with.")) }
    }

    private static func trimmed(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    @concurrent private static func section(_ git: URL, _ arguments: [String], at root: String, kind: GitDiffSection.Kind,
                                            safety: [String: String]) async throws -> GitDiffSection? {
        let patch = String(decoding: try await ReadCommand.run(git, arguments, at: root, limit: 524_288, gitConfiguration: safety), as: UTF8.self)
        return patch.isEmpty ? nil : GitDiffSection(kind: kind, patch: patch)
    }

    @concurrent static func remote(for local: LocalGitSnapshot) async throws -> RemoteSnapshot {
        switch await hosting(at: local.root) {
        case .github: try await github(at: local.root, branch: local.branch, headSHA: local.headSHA)
        case .gitlab: try await gitlab(at: local.root, branch: local.branch, headSHA: local.headSHA)
        }
    }

    @concurrent static func hosting(at root: String) async -> GitHosting {
        let configuration = try? await GitFilterGuard.shared.configuration(at: root)
        return configuration?.remotes.primaryURL.map(GitHosting.init(remoteURL:)) ?? .github
    }

    @concurrent static func gitlab(at path: String, branch: GitBranch?, headSHA: String?, executable override: URL? = nil) async throws -> RemoteSnapshot {
        guard let glab = override ?? ReadCommand.executable("glab") else {
            throw ReadCommandError(message: String(localized: "GitLab CLI isn’t installed. Install glab, then run glab auth login in a terminal."))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func api<Value: Decodable>(_ endpoint: String, as type: Value.Type) async throws -> Value {
            try decoder.decode(Value.self, from: try await ReadCommand.run(glab, ["api", endpoint], at: path))
        }
        let repository = try await api("projects/:id", as: GitLabProject.self).repository
        var changeRequest: ChangeRequest?
        var changeRequestError: String?
        if let branch, !branch.isDetached {
            do {
                let requests = try await api("projects/:id/merge_requests?source_branch=\(queryValue(branch.name))&order_by=updated_at&per_page=20",
                                             as: [GitLabMergeRequest].self)
                if let summary = requests.first(where: \.isOpen) ?? requests.first {
                    let request = try await api("projects/:id/merge_requests/\(summary.iid)", as: GitLabMergeRequest.self)
                    var jobs: [GitLabJob]?
                    if let pipeline = request.headPipeline {
                        jobs = try? await api(pipeline.jobsEndpoint, as: [GitLabJob].self)
                    }
                    changeRequest = request.changeRequest(checks: jobs?.map(\.check))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { changeRequestError = error.localizedDescription }
        }
        var runs: [PipelineRun] = []
        var checksError: String?
        if let headSHA {
            do {
                runs = try await api("projects/:id/pipelines?sha=\(queryValue(headSHA))&per_page=10", as: [GitLabPipeline].self).map(\.run)
            } catch is CancellationError { throw CancellationError() }
            catch { checksError = error.localizedDescription }
        }
        return RemoteSnapshot(hosting: .gitlab, repository: repository, changeRequest: changeRequest, runs: runs,
                              changeRequestError: changeRequestError, checksError: checksError)
    }

    private static func queryValue(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    @concurrent static func github(at path: String, branch: GitBranch?, headSHA: String?, executable override: URL? = nil) async throws -> RemoteSnapshot {
        guard let gh = override ?? ReadCommand.executable("gh") else {
            throw ReadCommandError(message: String(localized: "GitHub CLI isn’t installed. Install gh, then run gh auth login in a terminal."))
        }
        let decoder = JSONDecoder()
        let repoData = try await ReadCommand.run(gh, ["repo", "view", "--json", "nameWithOwner,url,description"], at: path)
        let repository = try decoder.decode(RemoteRepository.self, from: repoData)
        var pr: ChangeRequest?
        var prError: String?
        if let branch, !branch.isDetached {
            do {
                let data = try await ReadCommand.run(gh, ["pr", "view", branch.name, "--repo", repository.url,
                    "--json", "number,title,url,state,isDraft,headRefName,headRefOid,baseRefName,reviewDecision,statusCheckRollup"], at: path)
                pr = try decoder.decode(ChangeRequest.self, from: data)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if !error.localizedDescription.lowercased().contains("no pull requests found") {
                    prError = error.localizedDescription
                }
            }
        }
        var runs: [PipelineRun] = []
        var checksError: String?
        if let headSHA {
            do {
                let data = try await ReadCommand.run(gh, ["run", "list", "--repo", repository.url, "--commit", headSHA, "--limit", "10",
                    "--json", "databaseId,displayTitle,workflowName,status,conclusion,headSha,url"], at: path)
                runs = try decoder.decode([PipelineRun].self, from: data)
            } catch is CancellationError { throw CancellationError() }
            catch { checksError = error.localizedDescription }
        }
        return RemoteSnapshot(repository: repository, changeRequest: pr, runs: runs, changeRequestError: prError, checksError: checksError)
    }
}
