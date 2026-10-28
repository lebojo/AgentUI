import SwiftUI

struct BranchBadge: View {
    let branch: GitBranch
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        guard !branch.isDetached else { return .primary }
        return colorScheme == .dark ? Color(red: 0.52, green: 0.87, blue: 0.62) : Color(red: 0.12, green: 0.38, blue: 0.20)
    }
    private var background: Color {
        guard !branch.isDetached else { return Color(nsColor: .controlBackgroundColor) }
        return colorScheme == .dark ? Color(red: 0.14, green: 0.25, blue: 0.18) : Color(red: 0.90, green: 0.96, blue: 0.91)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: branch.isDetached ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(branch.name).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(background, in: Capsule())
        .help(branch.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(branch.accessibilityLabel)
    }
}
