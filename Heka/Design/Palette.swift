import SwiftUI

enum Palette {
    static let accent = Color.accentColor

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.systemTertiaryLabel

    static let surface = Color.systemSurface
    static let control = Color.systemControl
    static let fill = Color.systemFill
    static let bar = Material.bar
    static let searchFieldFill = fill.opacity(0.6)

    static let selectionFill = accent.opacity(0.18)
    static let focusedPaneFill = accent.opacity(0.12)
    static let dropTargetFill = accent.opacity(0.2)

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let agentWorking = Color.yellow
    static let codeBackground = Color.white

    static let branchForeground = Color(.branchForeground)
    static let branchBackground = Color(.branchBackground)

    static let diffAdditionBackground = Color(.diffAdditionBackground)
    static let diffDeletionBackground = Color(.diffDeletionBackground)
    static let diffHunkBackground = Color(.diffHunkBackground)
}
