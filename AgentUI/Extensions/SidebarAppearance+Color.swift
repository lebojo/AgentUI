import SwiftUI

extension SidebarTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension SidebarItemKind {
    var defaultColor: Color {
        switch self {
        case .folder: Palette.accent
        case .project: Palette.textSecondary
        }
    }
}

extension SidebarAppearance {
    var color: Color { tint?.color ?? kind.defaultColor }
}
