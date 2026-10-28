import Foundation

enum ConversationAgent: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var permissionBypassFlag: String {
        switch self {
        case .claude: "--dangerously-skip-permissions"
        case .codex: "--dangerously-bypass-approvals-and-sandbox"
        }
    }

    func launchCommand(skippingPermissions: Bool) -> [String] {
        [rawValue] + (skippingPermissions ? [permissionBypassFlag] : [])
    }
}

struct AgentConversation: Identifiable, Equatable, Sendable {
    let agent: ConversationAgent
    let sessionID: String
    let title: String
    let updatedAt: Date
    var isRunning = false

    var id: String { agent.rawValue + ":" + sessionID }

    var resumeCommand: [String] {
        switch agent {
        case .claude: ["claude", "--resume", sessionID]
        case .codex: ["codex", "resume", sessionID]
        }
    }
}
