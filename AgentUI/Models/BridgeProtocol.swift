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
    var command: [String]
    var force: Bool?
    var deleteBranch: Bool?
    var forceBranch: Bool?

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
    var branch: String?
    var branchDeleted: Bool?
}

extension BridgeResponse {
    init(deleting worktree: Worktree, of projectID: UUID, cleanup: BranchCleanup) {
        self.init(ok: true, message: cleanup.failure ?? cleanup.notice, projectID: projectID, worktreeID: worktree.id,
                  path: worktree.path, removed: true, branch: cleanup.branch, branchDeleted: cleanup.reportedDeletion)
    }
}
