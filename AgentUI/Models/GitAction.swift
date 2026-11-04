import Foundation

enum GitAction: Equatable, Sendable {
    case stage([String])
    case unstage([String])
    case stageAll
    case unstageAll
    case commit(title: String, message: String)
    case push
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
        case .push, .publish: String(localized: "Push")
        }
    }

    var symbol: String {
        switch self {
        case .stage, .stageAll: "plus"
        case .unstage, .unstageAll: "minus"
        case .commit: "checkmark"
        case .push, .publish: "arrow.up"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .commit: 3600
        case .push, .publish: 900
        default: 300
        }
    }

    var updatesRemote: Bool {
        switch self {
        case .push, .publish: true
        default: false
        }
    }

    static func commit(title: String, description: String) -> GitAction? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return .commit(title: title, message: description.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
