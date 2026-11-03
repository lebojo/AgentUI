@MainActor protocol TerminalSessionsDelegate: AnyObject {
    func terminalSessionsDidChangeAgents()
    func terminalSessionsDidRefreshAgents()
}
