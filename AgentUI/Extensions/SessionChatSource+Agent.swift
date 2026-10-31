extension SessionChatSource {
    init?(agent: ConversationAgent) {
        self.init(rawValue: agent.rawValue)
    }

    var agent: ConversationAgent? { ConversationAgent(rawValue: rawValue) }
}
