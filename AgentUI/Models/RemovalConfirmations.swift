import Foundation

struct RemovalConfirmations: Codable, Hashable, Sendable {
    var onProjectRemoval = true
    var onTerminalClosing = true

    func requires(_ removal: Removal) -> Bool {
        switch removal {
        case .project: onProjectRemoval
        case .terminal: onTerminalClosing
        case .worktree: true
        }
    }

    mutating func skip(_ removal: Removal) {
        switch removal {
        case .project: onProjectRemoval = false
        case .terminal: onTerminalClosing = false
        case .worktree: break
        }
    }
}
