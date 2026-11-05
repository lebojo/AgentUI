import Foundation

enum Removal: Hashable, Sendable {
    case project(UUID), terminal(UUID), worktree(projectID: UUID, worktreeID: UUID, name: String), orphanWorktree(path: String, name: String)

    static let branchLookupDeadline = Duration.milliseconds(300)

    var projectID: UUID? {
        switch self {
        case .project(let id): id
        case .terminal, .orphanWorktree: nil
        case .worktree(let projectID, _, _): projectID
        }
    }
    var allowsSkippingConfirmation: Bool {
        switch self {
        case .project, .terminal: true
        case .worktree, .orphanWorktree: false
        }
    }
    var actionTitle: String {
        switch self {
        case .project: String(localized: "Remove Project")
        case .terminal: String(localized: "Close Terminal")
        case .worktree: String(localized: "Delete Worktree")
        case .orphanWorktree: String(localized: "Move to Trash")
        }
    }
    var shortTitle: String {
        switch self {
        case .project: String(localized: "Remove")
        case .terminal: String(localized: "Close")
        case .worktree: String(localized: "Delete")
        case .orphanWorktree: String(localized: "Trash")
        }
    }
    var systemImage: String {
        switch self {
        case .project: "minus.circle"
        case .terminal: "xmark"
        case .worktree, .orphanWorktree: "trash"
        }
    }
    var title: String {
        switch self {
        case .project: String(localized: "Remove this project from the sidebar?")
        case .terminal: String(localized: "Close this terminal?")
        case .worktree(_, _, let name): String(localized: "Permanently delete the worktree “\(name)”?")
        case .orphanWorktree(_, let name): String(localized: "Move the worktree “\(name)” to the Trash?")
        }
    }
    private var confirmation: LocalizedStringResource {
        switch self {
        case .project: "Remove"
        case .terminal: "Close"
        case .worktree: "Delete Forever"
        case .orphanWorktree: "Move to Trash"
        }
    }
    private var message: LocalizedStringResource {
        switch self {
        case .project, .terminal:
            "The processes of the affected terminals will be stopped. Files and worktrees on disk will be kept."
        case .orphanWorktree:
            "Its folder, including uncommitted changes, goes to the Trash, where you can restore it. Its branch and commits stay in the repository."
        case .worktree:
            "Its terminals will be closed and its folder will be erased from disk, including uncommitted changes. This can’t be undone. The branch and its commits stay in the repository."
        }
    }

    func confirmation(deletableBranch branch: String?) -> LocalizedStringResource {
        guard case .worktree = self, branch != nil else { return confirmation }
        return "Delete Worktree Only"
    }

    func message(deletableBranch branch: String?) -> LocalizedStringResource {
        guard case .worktree = self, let branch else { return message }
        return LocalizedStringResource("Its terminals will be closed and its folder will be erased from disk, including uncommitted changes. This can’t be undone. You can keep the branch “\(branch)” and its commits in the repository, or delete it too if it’s merged into the main branch.",
                                       comment: "Message of the worktree deletion dialog; the variable is the branch name.")
    }
}
