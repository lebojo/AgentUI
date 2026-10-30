import Foundation

/// Only input/display switches not exposed by SwiftTerm. This bounded scanner never
/// retains output or interprets printable text; the Mac emulator owns the screen.
struct TerminalMirrorModes {
    private enum State { case ground, escape, csi, osc, string }
    private var state = State.ground
    private var parameters: [UInt8] = []
    private var overflow = false
    private var utf8Remaining = 0
    private(set) var modes: [Int: Bool] = [25: true, 7: true]
    private(set) var mouseEncoding = 0
    private(set) var insert = false
    private(set) var newline = false
    private static let tracked: Set<Int> = [5, 6, 7, 25, 66, 69, 1004]

    mutating func append(_ data: Data) {
        for byte in data {
            if utf8Remaining > 0 {
                if (0x80...0xbf).contains(byte) { utf8Remaining -= 1; continue }
                utf8Remaining = 0
            }
            if byte >= 0xc2 {
                utf8Remaining = byte <= 0xdf ? 1 : (byte <= 0xef ? 2 : (byte <= 0xf4 ? 3 : 0))
                continue
            }
            if byte == 0x18 || byte == 0x1a || byte == 0x9c { state = .ground; continue }
            if byte == 0x1b { state = .escape; continue }
            if byte == 0x9b { state = .csi; parameters = []; overflow = false; continue }
            if byte == 0x9d || byte == 0x9f { state = .osc; continue }
            if byte == 0x90 || byte == 0x98 || byte == 0x9e { state = .string; continue }
            switch state {
            case .ground: break
            case .escape:
                switch byte {
                case 0x5b: state = .csi; parameters = []; overflow = false
                case 0x5d, 0x5f: state = .osc
                case 0x50, 0x5e, 0x58: state = .string
                case 0x3d: modes[66] = true; state = .ground
                case 0x3e: modes[66] = false; state = .ground
                case 0x63: self = Self()
                default: state = .ground
                }
            case .csi:
                if (0x40...0x7e).contains(byte) {
                    if !overflow { apply(final: byte) }
                    state = .ground
                } else if (0x20...0x3f).contains(byte) {
                    if parameters.count < 256 { parameters.append(byte) } else { overflow = true }
                }
            case .osc:
                if byte == 7 { state = .ground }
            case .string: break
            }
        }
    }

    private mutating func apply(final: UInt8) {
        let value = String(decoding: parameters, as: UTF8.self)
        if final == 0x70 && value == "!" {
            modes[25] = true; modes[6] = false; modes[7] = true; modes[66] = false
            insert = false; newline = false
            return
        }
        guard final == 0x68 || final == 0x6c else { return }
        let enabled = final == 0x68
        let isPrivate = value.hasPrefix("?")
        let body = isPrivate ? String(value.dropFirst()) : value
        guard body.utf8.allSatisfy({ (48...57).contains($0) || $0 == 59 }) else { return }
        let numbers = body.split(separator: ";").compactMap { Int($0) }
        for number in numbers {
            if isPrivate {
                if [47, 1047, 1049].contains(number) { modes[25] = true }
                if Self.tracked.contains(number) { modes[number] = enabled }
                if [1005, 1006, 1015, 1016].contains(number) { mouseEncoding = enabled ? number : 0 }
            } else {
                if number == 4 { insert = enabled }
                if number == 20 { newline = enabled }
            }
        }
    }
}
