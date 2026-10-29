import Foundation

enum InspectorTab: String, CaseIterable, Identifiable {
    case files, agents, git, checks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .files: "Fichiers"
        case .agents: "Agents"
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

struct ExplorerEntry: Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct GitChange: Identifiable, Equatable, Sendable {
    let path: String
    let originalPath: String?
    let indexStatus: String
    let worktreeStatus: String
    var id: String { path }
    var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }
    var status: String { isUntracked ? "?" : [indexStatus, worktreeStatus].filter { $0 != " " }.joined() }
    var description: String {
        if isUntracked { return "Non suivi" }
        if status.contains("U") || ["AA", "DD"].contains(status) { return "Conflit" }
        if status.contains("R") { return "Renommé" }
        if status.contains("D") { return "Supprimé" }
        if status.contains("A") { return "Ajouté" }
        return "Modifié"
    }

    static func parsePorcelain(_ data: Data) -> [GitChange] {
        let fields = String(decoding: data, as: UTF8.self).components(separatedBy: "\0")
        var result: [GitChange] = []
        var index = 0
        while index < fields.count {
            let entry = fields[index]
            index += 1
            guard entry.count >= 4 else { continue }
            let x = String(entry.prefix(1))
            let y = String(entry.dropFirst().prefix(1))
            let path = String(entry.dropFirst(3))
            var original: String?
            if [x, y].contains(where: { $0 == "R" || $0 == "C" }), index < fields.count {
                original = fields[index]
                index += 1
            }
            result.append(GitChange(path: path, originalPath: original, indexStatus: x, worktreeStatus: y))
        }
        return result
    }
}

struct LocalGitSnapshot: Equatable, Sendable {
    let root: String
    let branch: GitBranch?
    let headSHA: String?
    let changes: [GitChange]
}

enum GitHosting: String, Sendable {
    case github, gitlab

    init(remoteURL: String) {
        self = Self.host(of: remoteURL).contains("gitlab") ? .gitlab : .github
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
        case .github: "Pull request"
        case .gitlab: "Merge request"
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
        case .github: "Actions"
        case .gitlab: "Pipelines"
        }
    }

    var noRunsMessage: String {
        switch self {
        case .github: "Aucune exécution GitHub Actions pour ce commit."
        case .gitlab: "Aucun pipeline GitLab pour ce commit."
        }
    }

    private static func host(of remoteURL: String) -> String {
        let value = remoteURL.lowercased()
        if let host = URL(string: value)?.host { return host }
        let address = value.split(separator: ":").first.map(String.init) ?? value
        return address.split(separator: "@").last.map(String.init) ?? address
    }
}

struct RemoteRepository: Decodable, Equatable, Sendable {
    let nameWithOwner: String
    let url: String
    let description: String?
}

struct RemoteCheck: Decodable, Identifiable, Equatable, Sendable {
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

struct ChangeRequest: Decodable, Equatable, Sendable {
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

struct PipelineRun: Decodable, Identifiable, Equatable, Sendable {
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

struct RemoteSnapshot: Equatable, Sendable {
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
