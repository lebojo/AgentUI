extension SessionChatSource {
    var agent: ConversationAgent? {
        switch self {
        case .terminal: nil
        case .claude: .claude
        case .codex: .codex
        case .copilot: .copilot
        }
    }

    var interruptKey: UInt8 { self == .terminal ? 3 : 27 }
}
