import Foundation

enum TerminalKey: Equatable, Sendable {
    case enter, escape, tab, backTab, backspace, delete, space
    case up, down, left, right, home, end, pageUp, pageDown
    case control(UInt8)

    static let maximumCount = 50
    static let names = "enter, escape, tab, shift-tab, backspace, delete, space, up, down, left, right, home, end, page-up, page-down, ctrl-a … ctrl-z"

    init?(name: String) {
        switch name.lowercased() {
        case "enter", "return": self = .enter
        case "escape", "esc": self = .escape
        case "tab": self = .tab
        case "shift-tab": self = .backTab
        case "backspace": self = .backspace
        case "delete": self = .delete
        case "space": self = .space
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        case "home": self = .home
        case "end": self = .end
        case "page-up": self = .pageUp
        case "page-down": self = .pageDown
        case let control where control.hasPrefix("ctrl-") && control.utf8.count == 6:
            guard let letter = control.utf8.last, (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(letter) else { return nil }
            self = .control(letter & 0x1f)
        default: return nil
        }
    }

    func bytes(applicationCursor: Bool) -> [UInt8] {
        let cursor: [UInt8] = applicationCursor ? [27, UInt8(ascii: "O")] : [27, UInt8(ascii: "[")]
        return switch self {
        case .enter: [13]
        case .escape: [27]
        case .tab: [9]
        case .backTab: Array("\u{1b}[Z".utf8)
        case .backspace: [127]
        case .delete: Array("\u{1b}[3~".utf8)
        case .space: [32]
        case .up: cursor + [UInt8(ascii: "A")]
        case .down: cursor + [UInt8(ascii: "B")]
        case .right: cursor + [UInt8(ascii: "C")]
        case .left: cursor + [UInt8(ascii: "D")]
        case .home: cursor + [UInt8(ascii: "H")]
        case .end: cursor + [UInt8(ascii: "F")]
        case .pageUp: Array("\u{1b}[5~".utf8)
        case .pageDown: Array("\u{1b}[6~".utf8)
        case .control(let code): [code]
        }
    }
}
