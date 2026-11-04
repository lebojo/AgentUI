import Foundation

struct WorkInProgressItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let agent: ConversationAgent?
    let projectName: String
    let worktreeName: String

    var location: String { "\(projectName) · \(worktreeName)" }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [name, projectName, worktreeName].contains { $0.localizedStandardContains(query) }
    }
}

struct WorkInProgressGroup: Identifiable, Equatable, Sendable {
    let status: AgentStatus
    let items: [WorkInProgressItem]

    var id: AgentStatus { status }
}

enum WorkInProgress {
    static let expansionID = UUID(uuidString: "5E4A9C1D-7B2F-4E8A-9D3C-1F6B8A2E4C70")!

    static func groups(in projects: [Project], statuses: [UUID: AgentStatus], agents: [UUID: ConversationAgent],
                       query: String) -> [WorkInProgressGroup] {
        guard !statuses.isEmpty else { return [] }
        var items: [AgentStatus: [WorkInProgressItem]] = [:]
        for project in projects {
            for worktree in project.worktrees {
                for terminal in worktree.terminals {
                    guard let status = statuses[terminal.id] else { continue }
                    let item = WorkInProgressItem(id: terminal.id, name: terminal.name, agent: agents[terminal.id],
                                                  projectName: project.name, worktreeName: worktree.displayName)
                    guard item.matches(query) else { continue }
                    items[status, default: []].append(item)
                }
            }
        }
        return AgentStatus.attentionOrder.compactMap { status in
            items[status].map { WorkInProgressGroup(status: status, items: $0) }
        }
    }
}
