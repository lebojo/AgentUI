import SwiftUI

extension AgentStatus {
    var color: Color {
        switch self {
        case .working: Palette.agentWorking
        case .ready: Palette.success
        case .waitingForInput: Palette.warning
        }
    }
}
