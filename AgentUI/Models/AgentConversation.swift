import Foundation

enum ConversationAgent: String, Sendable {
    case claude, codex

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
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
