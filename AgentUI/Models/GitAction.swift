import Foundation

enum GitAction: Equatable, Sendable {
    case stage([String])
    case unstage([String])
    case stageAll
    case unstageAll
    case commit(title: String, message: String)
    case push
    case pushUpstream(GitUpstream)
    case publish(remote: String, branch: String)

    var arguments: [String] {
        switch self {
        case .stage(let paths): ["--literal-pathspecs", "add", "--"] + paths
        case .unstage(let paths): ["--literal-pathspecs", "reset", "--quiet", "--"] + paths
        case .stageAll: ["add", "--all"]
        case .unstageAll: ["reset", "--quiet", "--", "."]
        case .commit(let title, let message):
            ["commit", "--message", title] + (message.isEmpty ? [] : ["--message", message])
        case .push: ["push"]
        case .pushUpstream(let upstream): ["push", upstream.remote, "HEAD:refs/heads/" + upstream.branch]
        case .publish(let remote, let branch): ["push", "--set-upstream", remote, "HEAD:refs/heads/" + branch]
        }
    }

    var title: String {
        switch self {
        case .stage: String(localized: "Stage")
        case .unstage: String(localized: "Unstage")
        case .stageAll: String(localized: "Stage All")
        case .unstageAll: String(localized: "Unstage All")
        case .commit: String(localized: "Commit")
        case .push, .pushUpstream, .publish: String(localized: "Push")
        }
    }

    var failureTitle: String {
        switch self {
        case .stage(let paths): String(localized: "Couldn’t stage \(Self.fileName(paths))")
        case .unstage(let paths): String(localized: "Couldn’t unstage \(Self.fileName(paths))")
        case .stageAll: String(localized: "Couldn’t stage all changes")
        case .unstageAll: String(localized: "Couldn’t unstage all changes")
        case .commit: String(localized: "Couldn’t commit")
        case .push, .pushUpstream: String(localized: "Couldn’t push")
        case .publish(_, let branch): String(localized: "Couldn’t publish \(branch)")
        }
    }

    var symbol: String {
        switch self {
        case .stage, .stageAll: "plus"
        case .unstage, .unstageAll: "minus"
        case .commit: "checkmark"
        case .push, .pushUpstream, .publish: "arrow.up"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .commit: 3600
        case .push, .pushUpstream, .publish: 900
        default: 300
        }
    }

    var updatesRemote: Bool {
        switch self {
        case .push, .pushUpstream, .publish: true
        default: false
        }
    }

    func retries(_ failed: GitAction) -> Bool {
        switch (self, failed) {
        case (.commit, .commit): true
        default: (updatesRemote && failed.updatesRemote) || self == failed
        }
    }

    static func commit(title: String, description: String) -> GitAction? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return .commit(title: title, message: description.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func fileName(_ paths: [String]) -> String {
        paths.first.map { ($0 as NSString).lastPathComponent } ?? ""
    }
}

struct GitActionFailure: Equatable, Sendable {
    let action: GitAction
    let error: String

    var message: String { String(localized: "\(action.failureTitle): \(error)") }
}
