import SwiftUI

struct DiffStats: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text("+\(additions)").foregroundStyle(Palette.success)
            Text("−\(deletions)").foregroundStyle(Palette.danger)
        }
        .font(Typography.captionMono)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(additions) ajouts, \(deletions) suppressions")
    }
}
