import Foundation

struct AgentLaunch: Codable, Hashable, Sendable {
    enum Trigger: Sendable {
        case newTerminal, newWorktree
    }

    var agent: ConversationAgent = .claude
    var onNewWorktree = false
    var onNewTerminal = false
    var skipsPermissions = false

    var previewCommand: String { agent.launchCommand(skippingPermissions: skipsPermissions).joined(separator: " ") }

    func launches(on trigger: Trigger) -> Bool {
        switch trigger {
        case .newTerminal: onNewTerminal
        case .newWorktree: onNewWorktree
        }
    }

    func command(on trigger: Trigger) -> [String] {
        launches(on: trigger) ? agent.launchCommand(skippingPermissions: skipsPermissions) : []
    }

    func terminalName(on trigger: Trigger) -> String {
        launches(on: trigger) ? agent.title : "Terminal"
    }
}
