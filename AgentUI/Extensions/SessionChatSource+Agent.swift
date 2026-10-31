extension SessionChatSource {
    var agent: ConversationAgent? {
        switch self {
        case .terminal: nil
        case .claude: .claude
        case .codex: .codex
        case .copilot: .copilot
        }
    }
}
