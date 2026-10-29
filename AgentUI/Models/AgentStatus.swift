import Foundation

enum AgentStatus: Equatable, Sendable {
    case working, ready, waitingForInput

    static let outputActivityWindow: TimeInterval = 2

    static let approvalPrompts = [
        "Would you like to run the following command",
        "Would you like to make the following edits",
        "Would you like to grant these permissions",
        "Would you like to send input",
        "Do you want to proceed",
        "Do you want to make this edit",
        "Do you want to run",
        "Do you want to allow",
        "No, and tell",
        "Permission required",
        "Allow once",
    ]

    init?(claudeStatus: String) {
        switch claudeStatus {
        case "busy", "shell": self = .working
        case "idle": self = .ready
        case "waiting": self = .waitingForInput
        default: return nil
        }
    }

    init(screen lines: [String], lastOutput: Date, now: Date = .now) {
        if lines.contains(where: { line in Self.approvalPrompts.contains { line.contains($0) } }) {
            self = .waitingForInput
        } else if now.timeIntervalSince(lastOutput) < Self.outputActivityWindow {
            self = .working
        } else {
            self = .ready
        }
    }

    var title: String {
        switch self {
        case .working: "Working"
        case .ready: "Ready"
        case .waitingForInput: "Waiting input"
        }
    }
}
