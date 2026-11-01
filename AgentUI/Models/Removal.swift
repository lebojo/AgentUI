import Foundation

enum Removal: Hashable, Sendable {
    case project(UUID), terminal(UUID), worktree(projectID: UUID, worktreeID: UUID, name: String)

    var projectID: UUID? {
        switch self {
        case .project(let id): id
        case .terminal: nil
        case .worktree(let projectID, _, _): projectID
        }
    }
    var allowsSkippingConfirmation: Bool {
        switch self {
        case .project, .terminal: true
        case .worktree: false
        }
    }
    var actionTitle: String {
        switch self {
        case .project: String(localized: "Remove Project")
        case .terminal: String(localized: "Close Terminal")
        case .worktree: String(localized: "Delete Worktree")
        }
    }
    var shortTitle: String {
        switch self {
        case .project: String(localized: "Remove")
        case .terminal: String(localized: "Close")
        case .worktree: String(localized: "Delete")
        }
    }
    var systemImage: String {
        switch self {
        case .project: "minus.circle"
        case .terminal: "xmark"
        case .worktree: "trash"
        }
    }
    var title: String {
        switch self {
        case .project: String(localized: "Remove this project from the sidebar?")
        case .terminal: String(localized: "Close this terminal?")
        case .worktree(_, _, let name): String(localized: "Permanently delete the worktree “\(name)”?")
        }
    }
    var confirmation: String {
        switch self {
        case .project: String(localized: "Remove")
        case .terminal: String(localized: "Close")
        case .worktree: String(localized: "Delete Forever")
        }
    }
    var message: String {
        switch self {
        case .project, .terminal:
            String(localized: "The processes of the affected terminals will be stopped. Files and worktrees on disk will be kept.")
        case .worktree:
            String(localized: "Its terminals will be closed and its folder will be erased from disk, including uncommitted changes. This can’t be undone. The branch and its commits stay in the repository.")
        }
    }
}
