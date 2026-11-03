import SwiftUI

struct AgentShortcutBar: View {
    let agents: [ConversationAgent]
    let launch: (ConversationAgent) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(agents) { agent in
                Button { launch(agent) } label: {
                    Label {
                        Text(agent.title)
                    } icon: {
                        agent.logo.resizable().scaledToFit().frame(width: IconSize.xs, height: IconSize.xs)
                    }
                }
                .accessibilityLabel("Launch \(agent.title)")
            }
            Spacer(minLength: 0)
        }
        .font(Typography.caption)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Palette.bar)
    }
}
