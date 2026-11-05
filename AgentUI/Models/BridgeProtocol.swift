import Foundation

struct BridgeRequest: Codable, Sendable {
    var id: UUID
    var action: String
    var projectID: UUID?
    var worktreeID: UUID?
    var name: String?
    var branch: String?
    var path: String?
    var directory: String?
    var callerTerminalID: UUID?
    var command: [String]
    var force: Bool?
    var deleteBranch: Bool?
    var forceBranch: Bool?
    var terminalID: UUID?
    var text: String?
    var pressesEnter: Bool?
    var keys: [String]?
    var reply: Bool?
    var messages: Int?
    var lines: Int?
    var idleSeconds: Double?
    var waitsForExit: Bool?
    var timeoutSeconds: Double?

    var responseTimeout: Double {
        action == "terminal.wait" ? (timeoutSeconds ?? TerminalWait.defaultTimeout) + 30 : 120
    }

    var branchRemoval: BranchRemoval {
        get throws {
            guard deleteBranch == true else {
                if forceBranch == true {
                    throw WorkspaceError(message: String(localized: "--force-branch only applies with --delete-branch. Add --delete-branch to delete the branch."))
                }
                return .keep
            }
            return forceBranch == true ? .force : .merged(confirmed: nil)
        }
    }
}

struct BridgeResponse: Codable, Sendable {
    var ok: Bool
    var message: String?
    var projectID: UUID?
    var worktreeID: UUID?
    var terminalID: UUID?
    var path: String?
    var workspace: Workspace?
    var removed: Bool?
    var closesCaller: Bool?
    var branch: String?
    var branchDeleted: Bool?
    var output: String?
    var running: Bool?
    var exitCode: Int32?
    var agent: ConversationAgent?
    var status: String?
    var messages: [SessionMessage]?
}

extension BridgeResponse {
    init(deleting worktree: Worktree, of projectID: UUID, cleanup: BranchCleanup) {
        self.init(ok: true, message: cleanup.failure ?? cleanup.notice, projectID: projectID, worktreeID: worktree.id,
                  path: worktree.path, removed: true, branch: cleanup.branch, branchDeleted: cleanup.reportedDeletion)
    }
}

enum TerminalWait {
    static let defaultIdle: Double = 5
    static let defaultTimeout: Double = 120
    static let maximumTimeout: Double = 3600
    static let defaultLines = 50
    static let maximumLines = 10_000
    static let maximumMessages = 200
}
