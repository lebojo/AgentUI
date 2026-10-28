import AppKit
import SwiftTerm

extension TerminalView {
    func apply(_ appearance: TerminalAppearance) {
        font = appearance.nsFont
        if let palette = appearance.palette {
            nativeBackgroundColor = palette.background.nsColor
            nativeForegroundColor = palette.foreground.nsColor
            caretColor = palette.cursor.nsColor
            selectedTextBackgroundColor = palette.selection.nsColor
        } else {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                nativeBackgroundColor = .textBackgroundColor
                nativeForegroundColor = .textColor
                caretColor = .selectedControlColor
                selectedTextBackgroundColor = .selectedTextBackgroundColor
            }
        }
        installColors((appearance.palette?.ansi ?? TerminalTheme.terminalAppANSI).map(\.terminalColor))
        getTerminal().setCursorStyle(appearance.cursorStyle)
    }
}

private extension TerminalColor {
    var terminalColor: SwiftTerm.Color {
        SwiftTerm.Color(red8: UInt16((red * 255).rounded()), green8: UInt16((green * 255).rounded()), blue8: UInt16((blue * 255).rounded()))
    }
}

private extension TerminalAppearance {
    var cursorStyle: CursorStyle {
        switch (cursorShape, cursorBlinks) {
        case (.block, true): .blinkBlock
        case (.block, false): .steadyBlock
        case (.underline, true): .blinkUnderline
        case (.underline, false): .steadyUnderline
        case (.bar, true): .blinkBar
        case (.bar, false): .steadyBar
        }
    }
}
