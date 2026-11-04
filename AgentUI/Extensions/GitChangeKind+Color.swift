import SwiftUI

extension GitChangeKind {
    var color: Color {
        switch self {
        case .modified, .typeChanged: Palette.warning
        case .added, .untracked, .copied: Palette.success
        case .deleted, .conflicted: Palette.danger
        case .renamed: Palette.accent
        }
    }
}
