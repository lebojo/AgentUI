import SwiftUI

struct AgentConversationRow: View {
    let conversation: AgentConversation
    let resume: () -> Void

    private var resumeHelp: String {
        if !conversation.canResume { return String(localized: "Session ID not supported") }
        return conversation.isRunning ? String(localized: "This conversation is already open") : String(localized: "Resume in a new terminal")
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            conversation.agent.logo
                .resizable()
                .scaledToFit()
                .frame(width: IconSize.s, height: IconSize.s)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(conversation.title).lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    Text(conversation.agent.title)
                    Text("·")
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                    if conversation.isRunning {
                        Text("·")
                        Text("Running").foregroundStyle(Palette.success)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xs)
            Button(action: resume) { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .disabled(conversation.isRunning || !conversation.canResume)
                .help(resumeHelp)
                .accessibilityLabel("Resume \(conversation.title)")
        }
        .padding(.vertical, Spacing.xxs)
    }
}
