import AppKit

enum TerminalKeyRoute: Equatable, Sendable {
    struct Screen: Equatable, Sendable {
        var usesKittyKeyboard = false
        var showsAlternateBuffer = false
        var usesApplicationCursor = false

        var editsShellLine: Bool { !usesKittyKeyboard && !showsAlternateBuffer }
    }

    case composesCharacter
    case actsAsMeta
    case sends([UInt8])

    static let metaKeySetting = "terminalOptionAsMetaKey"

    init?(key: NSEvent.SpecialKey?, modifiers: NSEvent.ModifierFlags, optionAsMeta: @autoclosure () -> Bool,
          screen: @autoclosure () -> Screen) {
        let modifiers = modifiers.intersection([.shift, .control, .option, .command])
        if modifiers == .shift, let arrow = Self.horizontalArrow(for: key) {
            let screen = screen()
            guard screen.editsShellLine else { return nil }
            self = .sends([0x1B, UInt8(ascii: screen.usesApplicationCursor ? "O" : "["), arrow])
            return
        }
        guard modifiers.contains(.option), !modifiers.contains(.command) else { return nil }
        if modifiers == .option, let wordJump = Self.wordJump(for: key), screen().editsShellLine {
            self = .sends(wordJump)
        } else {
            self = key != nil || optionAsMeta() ? .actsAsMeta : .composesCharacter
        }
    }

    private static func horizontalArrow(for key: NSEvent.SpecialKey?) -> UInt8? {
        switch key {
        case .leftArrow: UInt8(ascii: "D")
        case .rightArrow: UInt8(ascii: "C")
        default: nil
        }
    }

    private static func wordJump(for key: NSEvent.SpecialKey?) -> [UInt8]? {
        switch key {
        case .leftArrow: [0x1B, UInt8(ascii: "b")]
        case .rightArrow: [0x1B, UInt8(ascii: "f")]
        default: nil
        }
    }
}
