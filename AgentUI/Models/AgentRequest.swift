import Foundation

enum AgentRequest: Hashable, Sendable {
    case commit
    case changeRequest(base: ComparisonBranch)

    func prompt(from prompts: AgentPrompts) -> String {
        switch self {
        case .commit: prompts.commit
        case .changeRequest(let base): prompts.changeRequest + "\n\nBase branch: \(base.name)"
        }
    }
}
