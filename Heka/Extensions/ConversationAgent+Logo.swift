import SwiftUI

extension ConversationAgent {
    var logo: Image {
        switch self {
        case .claude: Image(.claudeLogo)
        case .codex: Image(.codexLogo)
        case .copilot: Image(.copilotLogo)
        case .openCode: Image(.openCodeLogo)
        }
    }
}
