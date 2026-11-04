import SwiftUI

struct TerminalDropHighlight: View {
    let edge: DropEdge
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.m)
            .fill(Palette.accent.opacity(0.18))
            .strokeBorder(Palette.accent, lineWidth: Stroke.regular)
            .padding(Spacing.xs)
            .frame(width: edge.axis == .horizontal ? size.width / 2 : size.width,
                   height: edge.axis == .vertical ? size.height / 2 : size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
