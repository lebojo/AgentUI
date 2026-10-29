import Foundation

struct BridgeRequest: Codable, Sendable {
    var id: UUID
    var action: String
    var projectID: UUID?
    var worktreeID: UUID?
    var name: String?
    var branch: String?
    var path: String?
    var command: [String]
    var force: Bool?
}

struct BridgeResponse: Codable, Sendable {
    var ok: Bool
    var message: String?
    var projectID: UUID?
    var worktreeID: UUID?
    var terminalID: UUID?
    var path: String?
    var workspace: Workspace?
}

