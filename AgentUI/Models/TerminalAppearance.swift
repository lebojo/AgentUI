import Foundation

enum TerminalCursorShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case block, underline, bar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block: String(localized: "Block")
        case .underline: String(localized: "Underline")
        case .bar: String(localized: "Bar")
        }
    }
}

struct TerminalAppearance: Codable, Hashable, Sendable {
    static let fontSizes: ClosedRange<Double> = 9...24
    static let defaultFontSize: Double = 13
    static let mobileFontSizeKey = "mobileTerminalFontSize"

    var theme: TerminalTheme = .system
    var customPalette: TerminalPalette = .oneDark
    var fontFamily = ""
    var fontSize = Self.defaultFontSize
    var cursorShape: TerminalCursorShape = .block
    var cursorBlinks = false

    var palette: TerminalPalette? { theme == .custom ? customPalette : theme.palette }
    var isEditable: Bool { palette != nil }
    var usesSystemFont: Bool { fontFamily.isEmpty }

    mutating func select(_ theme: TerminalTheme) {
        if theme == .custom, let palette { customPalette = palette }
        self.theme = theme
    }

    mutating func setColor(_ color: TerminalColor, at keyPath: WritableKeyPath<TerminalPalette, TerminalColor>) {
        guard var edited = palette else { return }
        edited[keyPath: keyPath] = color
        customPalette = edited
        theme = .custom
    }
}
