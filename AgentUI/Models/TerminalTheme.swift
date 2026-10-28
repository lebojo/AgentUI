import Foundation

struct TerminalColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

struct TerminalPalette: Codable, Hashable, Sendable {
    var background: TerminalColor
    var foreground: TerminalColor
    var cursor: TerminalColor
    var selection: TerminalColor
    var ansi: [TerminalColor]

    init(background: UInt32, foreground: UInt32, cursor: UInt32, selection: UInt32, ansi: [UInt32]) {
        self.background = TerminalColor(hex: background)
        self.foreground = TerminalColor(hex: foreground)
        self.cursor = TerminalColor(hex: cursor)
        self.selection = TerminalColor(hex: selection)
        self.ansi = ansi.map(TerminalColor.init(hex:))
    }
}

enum TerminalTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, oneDark, dracula, tokyoNight, nord, gruvboxDark, solarizedDark, solarizedLight, githubLight, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Système"
        case .oneDark: "One Dark"
        case .dracula: "Dracula"
        case .tokyoNight: "Tokyo Night"
        case .nord: "Nord"
        case .gruvboxDark: "Gruvbox"
        case .solarizedDark: "Solarized sombre"
        case .solarizedLight: "Solarized clair"
        case .githubLight: "GitHub clair"
        case .custom: "Personnalisé"
        }
    }

    var palette: TerminalPalette? {
        switch self {
        case .system, .custom: nil
        case .oneDark: .oneDark
        case .dracula: .dracula
        case .tokyoNight: .tokyoNight
        case .nord: .nord
        case .gruvboxDark: .gruvboxDark
        case .solarizedDark: .solarizedDark
        case .solarizedLight: .solarizedLight
        case .githubLight: .githubLight
        }
    }

    static let terminalAppANSI: [TerminalColor] = [
        0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
        0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB
    ].map(TerminalColor.init(hex:))
}

extension TerminalPalette {
    static let oneDark = TerminalPalette(background: 0x282C34, foreground: 0xABB2BF, cursor: 0x528BFF, selection: 0x3E4451, ansi: [
        0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
        0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF
    ])

    static let dracula = TerminalPalette(background: 0x282A36, foreground: 0xF8F8F2, cursor: 0xF8F8F2, selection: 0x44475A, ansi: [
        0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
        0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF
    ])

    static let tokyoNight = TerminalPalette(background: 0x1A1B26, foreground: 0xC0CAF5, cursor: 0xC0CAF5, selection: 0x33467C, ansi: [
        0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
        0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5
    ])

    static let nord = TerminalPalette(background: 0x2E3440, foreground: 0xD8DEE9, cursor: 0xD8DEE9, selection: 0x434C5E, ansi: [
        0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
        0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4
    ])

    static let gruvboxDark = TerminalPalette(background: 0x282828, foreground: 0xEBDBB2, cursor: 0xEBDBB2, selection: 0x504945, ansi: [
        0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
        0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2
    ])

    static let solarizedDark = TerminalPalette(background: 0x002B36, foreground: 0x839496, cursor: 0x93A1A1, selection: 0x073642, ansi: solarizedANSI)

    static let solarizedLight = TerminalPalette(background: 0xFDF6E3, foreground: 0x657B83, cursor: 0x586E75, selection: 0xEEE8D5, ansi: solarizedANSI)

    static let githubLight = TerminalPalette(background: 0xFFFFFF, foreground: 0x24292F, cursor: 0x0969DA, selection: 0xB6D7FF, ansi: [
        0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
        0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F
    ])

    private static let solarizedANSI: [UInt32] = [
        0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
        0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3
    ]
}
