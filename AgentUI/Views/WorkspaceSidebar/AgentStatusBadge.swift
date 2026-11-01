import SwiftUI

struct AgentStatusBadge: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(status.color).frame(width: Dimension.Badge.statusDotSize, height: Dimension.Badge.statusDotSize)
            Text(status.title).lineLimit(1)
        }
        .font(Typography.xs.weight(.medium))
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
        .background(status.color.opacity(0.18), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
    }
}
