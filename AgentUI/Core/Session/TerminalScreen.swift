import Foundation
import SwiftTerm

struct TerminalScreen {
    let columns: Int
    let rows: Int
    let alternate: Bool
    let historyStart: Int
    let history: [String]
    let lines: [String]
    let state: String

    init(terminal: Terminal, modes: TerminalMirrorModes) {
        let columns = terminal.cols
        let rows = terminal.rows
        self.columns = columns
        self.rows = rows
        alternate = terminal.isCurrentBufferAlternate
        let first = terminal.buffer.totalLinesTrimmed
        let top = max(first, terminal.liveLineEnd - rows)
        func encodeLine(_ row: Int) -> String {
            guard let line = terminal.getScrollInvariantLine(row: row) else { return "" }
            var result = ""
            var attribute: Attribute?
            for column in 0..<columns {
                let cell = line[column]
                if cell.width == 0 { continue }
                if attribute != cell.attribute {
                    attribute = cell.attribute
                    result += Self.sgr(cell.attribute)
                }
                let character = terminal.getCharacter(for: cell)
                result += character.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) ? " " : String(character)
            }
            return result
        }
        historyStart = alternate ? top : max(first, top - min(200, 16_384 / max(1, columns)))
        history = (historyStart..<top).map(encodeLine)
        lines = (top..<(top + rows)).map(encodeLine)
        func mode(_ number: Int, _ enabled: Bool) -> String { "\u{1b}[?\(number)\(enabled ? "h" : "l")" }
        var tail = ""
        for number in [5, 25, 66, 1004] { tail += mode(number, modes.modes[number] ?? false) }
        tail += mode(1, terminal.applicationCursor)
        tail += mode(2004, terminal.bracketedPasteMode)
        tail += mode(1007, terminal.alternateScrollMode)
        tail += "\u{1b}[?9;1000;1002;1003l\u{1b}[?1005;1006;1015;1016l"
        let mouse: Int?
        switch terminal.mouseMode {
        case .off: mouse = nil
        case .x10: mouse = 9
        case .vt200: mouse = 1000
        case .buttonEventTracking: mouse = 1002
        case .anyEvent: mouse = 1003
        }
        if let mouse { tail += mode(mouse, true) }
        if modes.mouseEncoding != 0 { tail += mode(modes.mouseEncoding, true) }
        tail += "\u{1b}[=\(terminal.keyboardEnhancementFlags.rawValue)u"
        tail += "\u{1b}[\(modes.newline ? "20h" : "20l")"
        let style = (CursorStyle.allCases.firstIndex(of: terminal.options.cursorStyle) ?? 0) + 1
        tail += "\u{1b}[\(style) q"
        tail += "\u{1b}[\(terminal.buffer.scrollTop + 1);\(terminal.buffer.scrollBottom + 1)r"
        if modes.modes[69] == true {
            tail += mode(69, true) + "\u{1b}[\(terminal.buffer.marginLeft + 1);\(terminal.buffer.marginRight + 1)s"
        }
        let origin = modes.modes[6] == true
        tail += mode(6, origin)
        let cursor = terminal.getCursorLocation()
        let x = min(columns - 1, cursor.x) - (origin && modes.modes[69] == true ? terminal.buffer.marginLeft : 0)
        let y = cursor.y - (origin ? terminal.buffer.scrollTop : 0)
        tail += "\u{1b}[\(max(0, y) + 1);\(max(0, x) + 1)H"
        tail += mode(7, modes.modes[7] ?? true)
        tail += "\u{1b}[\(modes.insert ? "4h" : "4l")"
        tail += Self.sgr(terminal.currentAttribute)
        state = tail
    }

    func output(after previous: TerminalScreen?) -> (data: Data, reset: Bool) {
        let historyEnd = historyStart + history.count
        let previousEnd = previous.map { $0.historyStart + $0.history.count } ?? historyStart
        var reset = previous == nil || previous?.columns != columns || previous?.rows != rows || previous?.alternate != alternate
            || previousEnd < historyStart || previousEnd > historyEnd
        if let previous, !reset {
            let overlapStart = max(historyStart, previous.historyStart)
            for row in overlapStart..<previousEnd where history[row - historyStart] != previous.history[row - previous.historyStart] {
                reset = true
                break
            }
        }
        if !reset, previous?.lines == lines, previous?.state == state, previousEnd == historyEnd { return (Data(), false) }
        var result = ""
        if reset { result += "\u{1b}[?1047\(alternate ? "h" : "l")" }
        result += "\u{1b}[?6;69;7l\u{1b}[r\u{1b}[4l\u{1b}(B\u{f}"
        if reset { result += "\u{1b}[0m\u{1b}[3J\u{1b}[2J" }
        let appended = reset ? historyStart : max(historyStart, previousEnd)
        for row in appended..<historyEnd {
            result += "\u{1b}[1;1H\u{1b}[0m\u{1b}[2K" + history[row - historyStart]
            result += "\u{1b}[\(rows);1H\n"
        }
        for row in lines.indices where reset || appended < historyEnd || previous?.lines[row] != lines[row] {
            result += "\u{1b}[\(row + 1);1H\u{1b}[0m\u{1b}[2K" + lines[row]
        }
        result += state
        return (Data(result.utf8), reset)
    }

    private static func sgr(_ attribute: Attribute) -> String {
        var codes = ["0"]
        for (style, code) in [(CharacterStyle.bold, "1"), (.dim, "2"), (.italic, "3"), (.blink, "5"), (.inverse, "7"), (.invisible, "8"), (.crossedOut, "9")] {
            if attribute.style.contains(style) { codes.append(code) }
        }
        if attribute.style.contains(.underline) { codes.append("4:\(max(1, attribute.underlineStyle.rawValue))") }
        func color(_ value: Attribute.Color, channel: Int) -> String? {
            switch value {
            case .ansi256(let code): "\(channel);5;\(code)"
            case .trueColor(let red, let green, let blue): "\(channel);2;\(red);\(green);\(blue)"
            default: nil
            }
        }
        if let fg = color(attribute.fg, channel: 38) { codes.append(fg) }
        if let bg = color(attribute.bg, channel: 48) { codes.append(bg) }
        if let underline = attribute.underlineColor, let code = color(underline, channel: 58) { codes.append(code) }
        return "\u{1b}[" + codes.joined(separator: ";") + "m"
    }
}

extension Terminal {
    var liveLineEnd: Int {
        var low = buffer.totalLinesTrimmed
        var high = low + buffer.getCorrectBufferLength(rows)
        while low < high {
            let middle = low + (high - low) / 2
            if getScrollInvariantLine(row: middle) == nil { high = middle }
            else { low = middle + 1 }
        }
        return low
    }

    func recentText(limit: Int) -> String {
        var lines: [String] = []
        var size = 0
        var row = liveLineEnd - 1
        while row >= buffer.totalLinesTrimmed, size < limit, let line = getScrollInvariantLine(row: row) {
            let text = line.translateToString(trimRight: true)
            lines.append(text)
            size += text.utf8.count + 1
            row -= 1
        }
        return lines.reversed().joined(separator: "\n")
    }
}
