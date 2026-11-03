import Foundation

struct Subagent: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let status: SubagentStatus
    let startedAt: Date
    let journal: URL
    let isVisible: Bool
}

enum SubagentStatus: Equatable, Sendable {
    case working, done, stopped

    var title: String {
        switch self {
        case .working: String(localized: "Working")
        case .done: String(localized: "Done")
        case .stopped: String(localized: "Stopped")
        }
    }
}

struct SubagentSelection: Equatable, Sendable {
    let terminalID: UUID
    let subagent: Subagent
}
