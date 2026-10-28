import SwiftUI
import AppKit

extension TerminalColor {
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(nsColor: nsColor) }
}

extension TerminalAppearance {
    var nsFont: NSFont {
        let size = CGFloat(fontSize)
        guard !usesSystemFont, let font = NSFont(name: fontFamily, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return font
    }

    var font: Font { Font(nsFont) }
    var background: Color { palette?.background.color ?? Palette.surface }
    var foreground: Color { palette?.foreground.color ?? Palette.textPrimary }
    var cursor: Color { palette?.cursor.color ?? Palette.accent }
    var ansi: [Color] { (palette?.ansi ?? TerminalTheme.terminalAppANSI).map(\.color) }
}
