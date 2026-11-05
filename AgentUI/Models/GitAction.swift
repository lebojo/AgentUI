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
        case .pushUpstream(let upstream): ["push", "--", upstream.remote, "HEAD:refs/heads/" + upstream.branch]
        case .publish(let remote, let branch): ["push", "--set-upstream", "--", remote, "HEAD:refs/heads/" + branch]
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .stage: "Stage"
        case .unstage: "Unstage"
        case .stageAll: "Stage All"
        case .unstageAll: "Unstage All"
        case .commit: "Commit"
        case .push, .pushUpstream: "Push"
        case .publish: "Publish"
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .publish(let remote, let branch):
            LocalizedStringResource("Push this branch to a new \(remote)/\(branch) branch and track it",
                                    comment: "Help of the Publish button; the variables are a remote name and a branch name.")
        default: title
        }
    }

    var failureTitle: LocalizedStringResource {
        switch self {
        case .stage(let paths):
            LocalizedStringResource("Couldn’t stage \(Self.fileName(paths))", comment: "Title of a failed Git action; the variable is a file name.")
        case .unstage(let paths):
            LocalizedStringResource("Couldn’t unstage \(Self.fileName(paths))", comment: "Title of a failed Git action; the variable is a file name.")
        case .stageAll: "Couldn’t stage all changes"
        case .unstageAll: "Couldn’t unstage all changes"
        case .commit: "Couldn’t commit"
        case .push, .pushUpstream: "Couldn’t push"
        case .publish(_, let branch):
            LocalizedStringResource("Couldn’t publish \(branch)", comment: "Title of a failed Git action; the variable is a branch name.")
        }
    }

    func accessibilityLabel(for name: String) -> LocalizedStringResource {
        switch self {
        case .stage: LocalizedStringResource("Stage \(name)", comment: "Accessibility label of the button that stages one file; the variable is the file name.")
        case .unstage: LocalizedStringResource("Unstage \(name)", comment: "Accessibility label of the button that unstages one file; the variable is the file name.")
        default: title
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

    var message: LocalizedStringResource {
        LocalizedStringResource("\(action.failureTitle): \(error)", comment: "Failed Git action; the first variable is its title, the second the Git error.")
    }
}
