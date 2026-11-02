import SwiftUI

extension SubagentStatus {
    var color: Color {
        switch self {
        case .working: Palette.agentWorking
        case .done: Palette.success
        case .stopped: Palette.textSecondary
        }
    }
}
