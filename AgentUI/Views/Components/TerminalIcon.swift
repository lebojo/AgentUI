import SwiftUI

struct TerminalIcon: View {
    let agent: ConversationAgent?

    var body: some View {
        Group {
            if let agent {
                agent.logo.resizable().scaledToFit().frame(width: IconSize.s, height: IconSize.s)
            } else {
                Image(systemName: "terminal").font(Typography.m).foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }
}
