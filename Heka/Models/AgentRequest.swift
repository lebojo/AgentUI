import Foundation

enum AgentRequest: Hashable, Sendable {
    case commit
    case changeRequest(baseBranch: String)

    func prompt(from prompts: AgentPrompts) -> String {
        switch self {
        case .commit: prompts.commit
        case .changeRequest(let baseBranch): prompts.changeRequest + "\n\nBase branch: \(baseBranch)"
        }
    }
}
