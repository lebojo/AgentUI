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
        case .project: "Retirer le projet"
        case .terminal: "Fermer le terminal"
        case .worktree: "Supprimer le worktree"
        }
    }
    var shortTitle: String {
        switch self {
        case .project: "Retirer"
        case .terminal: "Fermer"
        case .worktree: "Supprimer"
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
        case .project: "Retirer ce projet de la barre latérale ?"
        case .terminal: "Fermer ce terminal ?"
        case .worktree(_, _, let name): "Supprimer définitivement le worktree « \(name) » ?"
        }
    }
    var confirmation: String {
        switch self {
        case .project: "Retirer"
        case .terminal: "Fermer"
        case .worktree: "Supprimer pour toujours"
        }
    }
    var message: String {
        switch self {
        case .project, .terminal:
            "Les processus des terminaux concernés seront arrêtés. Les fichiers et les worktrees sur disque seront conservés."
        case .worktree:
            "Ses terminaux seront fermés et son dossier sera effacé du disque, y compris les modifications non commitées. Cette action est irréversible. La branche et ses commits restent dans le dépôt."
        }
    }
}
