import SwiftUI

struct GitChangeOutlineRow<Content: View>: View {
    let depth: Int
    @ViewBuilder let content: Content

    var body: some View {
        content.padding(.leading, CGFloat(depth) * (IconSize.xs + Spacing.xs))
    }
}
