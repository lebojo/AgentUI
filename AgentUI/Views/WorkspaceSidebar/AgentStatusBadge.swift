import SwiftUI

struct AgentStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(color).frame(width: Dimension.Badge.statusDotSize, height: Dimension.Badge.statusDotSize)
            Text(title).lineLimit(1)
        }
        .font(Typography.xs.weight(.medium))
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
        .background(color.opacity(0.18), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
