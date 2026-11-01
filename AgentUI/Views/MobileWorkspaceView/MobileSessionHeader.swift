import SwiftUI

struct MobileSessionHeader: View {
    let project: String
    let worktree: String
    let agent: ConversationAgent?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Label(project, systemImage: "shippingbox")
            Image(systemName: "chevron.right")
            Label(worktree, systemImage: "arrow.triangle.branch")
            Spacer(minLength: Spacing.s)
            if let agent {
                agent.logo.resizable().scaledToFit()
                    .frame(width: IconSize.m, height: IconSize.m)
                    .accessibilityLabel(agent.title)
            }
        }
        .font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
    }
}
