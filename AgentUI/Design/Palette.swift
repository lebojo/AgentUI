import SwiftUI
import AppKit

enum Palette {
    static let accent = Color.accentColor

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let surface = Color(nsColor: .textBackgroundColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let fill = Color(nsColor: .quaternaryLabelColor)
    static let bar = Material.bar

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    static let branchForeground = Color(.branchForeground)
    static let branchBackground = Color(.branchBackground)

    static let diffAdditionBackground = Color(.diffAdditionBackground)
    static let diffDeletionBackground = Color(.diffDeletionBackground)
    static let diffHunkBackground = Color(.diffHunkBackground)
}
