import SwiftUI

extension GitDiffLine.Kind {
    var background: Color {
        switch self {
        case .addition: Palette.diffAdditionBackground
        case .deletion: Palette.diffDeletionBackground
        case .hunk: Palette.diffHunkBackground
        case .context, .meta: .clear
        }
    }

    var markerColor: Color {
        switch self {
        case .addition: Palette.success
        case .deletion: Palette.danger
        case .context, .hunk, .meta: Palette.textTertiary
        }
    }
}
