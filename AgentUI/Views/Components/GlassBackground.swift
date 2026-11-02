import SwiftUI

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content.glassEffect(.regular, in: .containerRelative)
        } else {
            content.background(Palette.bar, in: .containerRelative)
        }
    }
}
