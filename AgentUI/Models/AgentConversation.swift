import Foundation

enum ConversationAgent: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, copilot
    case openCode = "opencode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .openCode: "OpenCode"
        }
    }

    var permissionBypassFlag: String {
        switch self {
        case .claude: "--dangerously-skip-permissions"
        case .codex: "--dangerously-bypass-approvals-and-sandbox"
        case .copilot: "--allow-all"
        case .openCode: "--auto"
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

    static func isValidSessionID(_ sessionID: String) -> Bool {
        guard let first = sessionID.unicodeScalars.first, sessionID.utf8.count <= 128,
              CharacterSet.alphanumerics.contains(first) else { return false }
        return sessionID.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)) }
    }

    var canResume: Bool { Self.isValidSessionID(sessionID) }

    var resumeCommand: [String]? {
        guard canResume else { return nil }
        return switch agent {
        case .claude: ["claude", "--resume", sessionID]
        case .codex: ["codex", "resume", sessionID]
        case .copilot: ["copilot", "--resume", sessionID]
        case .openCode: ["opencode", "--session", sessionID]
        }
    }
}
