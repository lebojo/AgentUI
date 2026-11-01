import SwiftUI

struct BranchBadge: View {
    let branch: GitBranch

    private var foreground: Color { branch.isDetached ? Palette.textPrimary : Palette.branchForeground }
    private var background: Color { branch.isDetached ? Palette.control : Palette.branchBackground }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: branch.isDetached ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.triangle.branch")
                .font(Typography.xxs.weight(.medium))
            Text(branch.name).lineLimit(1).truncationMode(.middle)
        }
        .font(Typography.xs.weight(.medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
        .background(background, in: Capsule())
        .help(branch.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(branch.accessibilityLabel)
    }
}
