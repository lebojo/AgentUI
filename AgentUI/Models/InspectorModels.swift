import Foundation

enum InspectorTab: String, CaseIterable, Identifiable {
    case files, agents, git, checks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .files: String(localized: "Files")
        case .agents: String(localized: "Agents")
        case .git: "Git"
        case .checks: "Checks"
        }
    }
    var symbol: String {
        switch self {
        case .files: "doc.on.doc"
        case .agents: "square.grid.2x2"
        case .git: "arrow.triangle.branch"
        case .checks: "checklist"
        }
    }
}

struct ExplorerListing: Codable, Sendable {
    var entries: [ExplorerEntry]
    var omitted = 0
}

struct ExplorerEntry: Codable, Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct GitChange: Codable, Identifiable, Equatable, Sendable {
    let path: String
    let originalPath: String?
    let indexStatus: String
    let worktreeStatus: String
    var id: String { path }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    var directories: [String] { path.split(separator: "/").dropLast().map(String.init) }
    var paths: [String] { [path] + (originalPath.map { [$0] } ?? []) }
    var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }
    var isConflicted: Bool { status.contains("U") || ["AA", "DD"].contains(status) }
    var isStaged: Bool { !isUntracked && !isConflicted && indexStatus != " " }
    var isUnstaged: Bool { isUntracked || isConflicted || worktreeStatus != " " }
    var status: String { isUntracked ? "?" : [indexStatus, worktreeStatus].filter { $0 != " " }.joined() }

    static func parseNameStatus(_ data: Data) -> [GitChange] {
        let fields = String(decoding: data, as: UTF8.self).components(separatedBy: "\0")
        var result: [GitChange] = []
        var index = 0
        while index + 1 < fields.count {
            let status = String(fields[index].prefix(1))
            index += 1
            guard !status.isEmpty else { continue }
            if status == "R" || status == "C", index + 1 < fields.count {
                result.append(GitChange(path: fields[index + 1], originalPath: fields[index], indexStatus: status, worktreeStatus: " "))
                index += 2
            } else {
                result.append(GitChange(path: fields[index], originalPath: nil, indexStatus: status, worktreeStatus: " "))
                index += 1
            }
        }
        return result
    }
}

enum GitChangeKind: Sendable {
    case modified, added, deleted, renamed, copied, typeChanged, untracked, conflicted

    init(code: String) {
        switch code {
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "?": self = .untracked
        case "U": self = .conflicted
        default: self = .modified
        }
    }

    var letter: String {
        switch self {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .untracked: "U"
        case .conflicted: "!"
        }
    }

    var title: String {
        switch self {
        case .modified, .typeChanged: String(localized: "Modified")
        case .added: String(localized: "Added")
        case .deleted: String(localized: "Deleted")
        case .renamed: String(localized: "Renamed")
        case .copied: String(localized: "Copied")
        case .untracked: String(localized: "Untracked")
        case .conflicted: String(localized: "Conflict")
        }
    }
}

enum GitChangeScope: Hashable, Sendable {
    case staged
    case unstaged
    case branch(ComparisonBranch)

    var emptyTitle: String {
        switch self {
        case .staged: String(localized: "No Staged Changes")
        case .unstaged: String(localized: "No Unstaged Changes")
        case .branch(let base): String(localized: "No differences with \(base.name)")
        }
    }

    var bulkAction: GitAction? {
        switch self {
        case .staged: .unstageAll
        case .unstaged: .stageAll
        case .branch: nil
        }
    }

    func title(count: Int) -> String {
        switch self {
        case .staged: String(localized: "Staged Changes · \(count)")
        case .unstaged, .branch: String(localized: "Changes · \(count)")
        }
    }

    func kind(of change: GitChange) -> GitChangeKind {
        switch self {
        case .unstaged where change.isConflicted: .conflicted
        case .unstaged: GitChangeKind(code: change.worktreeStatus)
        case .staged, .branch: GitChangeKind(code: change.indexStatus)
        }
    }

    func action(for change: GitChange) -> GitAction? {
        switch self {
        case .staged: .unstage(change.paths)
        case .unstaged: .stage([change.path])
        case .branch: nil
        }
    }
}

struct GitTracking: Codable, Equatable, Sendable {
    let upstream: String?
    var ahead = 0
    var remote: String?
    var tracksSameBranch: Bool?
    var goneUpstream: String?
    var namedUpstream: GitUpstream?
    var hasUnmergedWork: Bool?

    var isPublished: Bool { upstream != nil && (tracksSameBranch == true || namedUpstream != nil) }
    var hasUnpushedCommits: Bool { isPublished && ahead > 0 }

    func push(branch: String) -> GitAction? {
        if goneUpstream != nil { return hasUnmergedWork == true ? remote.map { .publish(remote: $0, branch: branch) } : nil }
        if upstream != nil, let namedUpstream { return ahead > 0 ? .pushUpstream(namedUpstream) : nil }
        guard isPublished else { return remote.map { .publish(remote: $0, branch: branch) } }
        return ahead > 0 ? .push : nil
    }

    func remoteBranch(for branch: String) -> String {
        namedUpstream?.branch ?? branch
    }
}

struct GitUpstream: Codable, Equatable, Sendable {
    let remote: String
    let branch: String
}

struct GitRemote: Equatable, Sendable {
    let name: String
    let url: String
}

struct GitRemoteConfiguration: Equatable, Sendable {
    private static let branchKeys = [".remote", ".pushremote", ".merge"]

    private(set) var remotes: [GitRemote] = []
    private var values: [String: String] = [:]

    var primaryURL: String? { (remotes.first { $0.name == "origin" } ?? remotes.first)?.url }

    func pushURL(for branch: String) -> String? {
        pushRemote(for: branch).flatMap(url(ofRemote:))
    }

    func url(ofRemote name: String) -> String? {
        remotes.first { $0.name == name }?.url
    }

    func upstream(of branch: String) -> GitUpstream? {
        let prefix = "refs/heads/"
        guard let remote = values["branch.\(branch).remote"], remotes.contains(where: { $0.name == remote }),
              let merge = values["branch.\(branch).merge"], merge.hasPrefix(prefix), merge.count > prefix.count else { return nil }
        return GitUpstream(remote: remote, branch: String(merge.dropFirst(prefix.count)))
    }

    init(entries: [(key: String, value: String)] = []) {
        for (key, value) in entries {
            if let name = Self.remoteName(fromURLKey: key) {
                if !remotes.contains(where: { $0.name == name }) { remotes.append(GitRemote(name: name, url: value)) }
            } else if Self.isTrackingSetting(key) {
                values[key] = value
            }
        }
    }

    func pushRemote(for branch: String) -> String? {
        let names = remotes.map(\.name).filter { !$0.hasPrefix("-") }
        let preferred = [values["branch.\(branch).pushremote"], values["remote.pushdefault"], values["branch.\(branch).remote"], "origin"]
        if let name = preferred.compactMap({ $0 }).first(where: names.contains) { return name }
        return names.count == 1 ? names.first : nil
    }

    func tracksSameBranch(_ branch: String) -> Bool {
        guard let remote = values["branch.\(branch).remote"], remotes.contains(where: { $0.name == remote }) else { return false }
        return values["branch.\(branch).merge"] == "refs/heads/" + branch
    }

    private static func isTrackingSetting(_ key: String) -> Bool {
        key == "remote.pushdefault" || (key.hasPrefix("branch.") && branchKeys.contains(where: key.hasSuffix))
    }

    private static func remoteName(fromURLKey key: String) -> String? {
        let prefix = "remote.", suffix = ".url"
        guard key.hasPrefix(prefix), key.hasSuffix(suffix), key.count > prefix.count + suffix.count else { return nil }
        return String(key.dropFirst(prefix.count).dropLast(suffix.count))
    }
}

struct ComparisonBranch: Codable, Hashable, Identifiable, Sendable {
    private static let prefixes = ["refs/heads/", "refs/remotes/"]

    let reference: String

    var id: String { reference }
    var isBranchReference: Bool {
        Self.prefixes.contains { reference.hasPrefix($0) && reference.count > $0.count } && !reference.contains("..")
            && !reference.contains(where: { $0.isWhitespace || "^~:?*[\\".contains($0) })
    }
    var name: String {
        Self.prefixes.first(where: reference.hasPrefix).map { String(reference.dropFirst($0.count)) } ?? reference
    }
    var hostedName: String {
        let parts = name.split(separator: "/", maxSplits: 1)
        return reference.hasPrefix("refs/remotes/") && parts.count == 2 ? String(parts[1]) : name
    }
}

struct GitBranchList: Codable, Equatable, Sendable {
    let branches: [ComparisonBranch]
    let defaultBranch: ComparisonBranch?
    var omitted = 0

    func preferred(over current: ComparisonBranch?) -> ComparisonBranch? {
        if let current, branches.contains(current) { return current }
        return defaultBranch ?? branches.first
    }
}

struct BranchComparison: Codable, Equatable, Sendable {
    let base: ComparisonBranch
    let commits: Int
    let changes: [GitChange]
    var omittedChanges = 0
}

struct LocalGitSnapshot: Codable, Equatable, Sendable {
    static let changeLimit = 10_000

    let root: String
    let branch: GitBranch?
    let headSHA: String?
    private(set) var changes: [GitChange]
    var omittedChanges = 0
    var isTruncated: Bool?
    var tracking: GitTracking?
    var webAddress: RemoteWebAddress?
    var pushWebAddress: RemoteWebAddress?

    var omission: WorkingTreeOmission { WorkingTreeOmission(count: omittedChanges, isTruncated: isTruncated == true) }
    var stagedChanges: [GitChange] { changes.filter(\.isStaged) }
    var unstagedChanges: [GitChange] { changes.filter(\.isUnstaged) }
    var push: GitAction? {
        guard headSHA != nil, let branch, !branch.isDetached else { return nil }
        return tracking?.push(branch: branch.name)
    }

    func limited(to changes: [GitChange], omitting omitted: Int) -> LocalGitSnapshot {
        var snapshot = self
        snapshot.changes = changes
        snapshot.omittedChanges += omitted
        return snapshot
    }
}

struct WorkingTreeOmission: Equatable, Sendable {
    let count: Int
    let isTruncated: Bool

    func message(includingBulkActions: Bool) -> String {
        let listed = isTruncated ? String(localized: "At least \(count) more changes aren’t listed.") : String(localized: "\(count) more changes aren’t listed.")
        guard includingBulkActions else { return listed }
        return listed + " " + String(localized: "Stage All and Unstage All also apply to them.")
    }
}

enum GitHosting: String, Codable, Sendable {
    case github, gitlab

    init(remoteURL: String) {
        self = Self(host: Self.host(of: remoteURL)) ?? .github
    }

    init?(host: String) {
        let host = host.lowercased()
        if host.contains("gitlab") { self = .gitlab }
        else if host.contains("github") { self = .github }
        else { return nil }
    }

    var title: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    var cli: String {
        switch self {
        case .github: "gh"
        case .gitlab: "glab"
        }
    }

    var changeRequestTitle: String {
        switch self {
        case .github: String(localized: "Pull request")
        case .gitlab: String(localized: "Merge request")
        }
    }

    var changeRequestPrefix: String {
        switch self {
        case .github: "#"
        case .gitlab: "!"
        }
    }

    var runsTitle: String {
        switch self {
        case .github: String(localized: "Actions")
        case .gitlab: String(localized: "Pipelines")
        }
    }

    var noRunsMessage: String {
        switch self {
        case .github: String(localized: "No GitHub Actions runs for this commit.")
        case .gitlab: String(localized: "No GitLab pipelines for this commit.")
        }
    }

    private static func host(of remoteURL: String) -> String {
        let value = remoteURL.lowercased()
        if let host = URL(string: value)?.host { return host }
        let address = value.split(separator: ":").first.map(String.init) ?? value
        return address.split(separator: "@").last.map(String.init) ?? address
    }
}

struct RemoteRepository: Codable, Equatable, Sendable {
    let nameWithOwner: String
    let url: String
    let description: String?
}

struct RemoteCheck: Codable, Identifiable, Equatable, Sendable {
    let name: String?
    let context: String?
    let status: String?
    let conclusion: String?
    let state: String?
    let detailsUrl: String?
    let targetUrl: String?
    var title: String { name ?? context ?? "Check" }
    var result: String { conclusion.flatMap { $0.isEmpty ? nil : $0 } ?? state ?? status ?? "PENDING" }
    var url: String? { detailsUrl ?? targetUrl }
    var id: String { title + (url ?? "") }
}

struct ChangeRequest: Codable, Equatable, Sendable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let headRefName: String
    let headRefOid: String
    let baseRefName: String
    let reviewDecision: String?
    let statusCheckRollup: [RemoteCheck]?
}

struct PipelineRun: Codable, Identifiable, Equatable, Sendable {
    let databaseId: Int
    let displayTitle: String
    let workflowName: String
    let status: String
    let conclusion: String
    let headSha: String
    let url: String
    var id: Int { databaseId }
    var result: String { conclusion.isEmpty ? status : conclusion }
}

struct RemoteSnapshot: Codable, Equatable, Sendable {
    var hosting: GitHosting = .github
    let repository: RemoteRepository
    let changeRequest: ChangeRequest?
    let runs: [PipelineRun]
    let changeRequestError: String?
    let checksError: String?
}

struct TextContent: Sendable {
    let text: String
    let isTruncated: Bool
}

struct TextPreview: Identifiable {
    var id = UUID()
    let title: String
    let text: String
    let url: URL?
}

enum InspectorPreview: Identifiable {
    case file(TextPreview)
    case diff(GitDiff)
    var id: UUID {
        switch self {
        case .file(let preview): preview.id
        case .diff(let diff): diff.id
        }
    }
}

struct GitLabProject: Decodable, Sendable {
    let pathWithNamespace: String
    let webUrl: String
    let description: String?

    var repository: RemoteRepository {
        RemoteRepository(nameWithOwner: pathWithNamespace, url: webUrl, description: description.flatMap { $0.isEmpty ? nil : $0 })
    }
}

struct GitLabPipeline: Decodable, Sendable {
    let id: Int
    let iid: Int?
    let name: String?
    let ref: String?
    let status: String
    let sha: String
    let webUrl: String

    var run: PipelineRun {
        PipelineRun(databaseId: id, displayTitle: ref ?? "Pipeline", workflowName: name ?? "Pipeline #\(iid ?? id)",
                    status: status, conclusion: GitLabStatus.conclusion(of: status), headSha: sha, url: webUrl)
    }
}

struct GitLabJob: Decodable, Sendable {
    let name: String
    let stage: String?
    let status: String
    let webUrl: String?

    var check: RemoteCheck {
        RemoteCheck(name: stage.map { "\($0) · \(name)" } ?? name, context: nil, status: status,
                    conclusion: GitLabStatus.conclusion(of: status), state: nil, detailsUrl: webUrl, targetUrl: nil)
    }
}

struct GitLabMergeRequest: Decodable, Sendable {
    struct Pipeline: Decodable, Sendable {
        let id: Int
        let projectId: Int

        var jobsEndpoint: String { "projects/\(projectId)/pipelines/\(id)/jobs?per_page=100" }
    }

    let iid: Int
    let title: String
    let webUrl: String
    let state: String
    let draft: Bool?
    let workInProgress: Bool?
    let sourceBranch: String
    let targetBranch: String
    let sha: String?
    let headPipeline: Pipeline?

    var isOpen: Bool { state == "opened" }

    func changeRequest(checks: [RemoteCheck]?) -> ChangeRequest {
        ChangeRequest(number: iid, title: title, url: webUrl, state: state == "opened" ? "OPEN" : state.uppercased(),
                      isDraft: draft ?? workInProgress ?? false, headRefName: sourceBranch, headRefOid: sha ?? "",
                      baseRefName: targetBranch, reviewDecision: nil, statusCheckRollup: checks)
    }
}

enum GitLabStatus {
    static func conclusion(of status: String) -> String {
        switch status {
        case "success": "SUCCESS"
        case "failed": "FAILURE"
        case "canceled", "canceling": "CANCELLED"
        case "skipped", "manual": "SKIPPED"
        default: ""
        }
    }
}
