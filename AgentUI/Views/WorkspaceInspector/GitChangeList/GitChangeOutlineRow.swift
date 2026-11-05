import SwiftUI

struct GitChangeOutlineRow<Content: View>: View {
    let depth: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.leading, CGFloat(depth) * (IconSize.xs + Spacing.xs))
    }
}
