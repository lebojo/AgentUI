import Foundation
import SwiftTerm

private final class Delegate: TerminalDelegate {
    var replies = Data()
    func send(source: Terminal, data: ArraySlice<UInt8>) { replies.append(contentsOf: data) }
}

@main struct TerminalMirrorTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() {
        let hostDelegate = Delegate(), peerDelegate = Delegate()
        let host = Terminal(delegate: hostDelegate), peer = Terminal(delegate: peerDelegate)
        host.resize(cols: 48, rows: 12)
        peer.resize(cols: 48, rows: 12)
        var modes = TerminalMirrorModes()
        var previous: TerminalScreen?
        func feed(_ value: String) {
            let bytes = Data(value.utf8)
            modes.append(bytes)
            host.feed(byteArray: Array(bytes))
        }
        func sync(full: Bool = false) {
            let screen = TerminalScreen(terminal: host, modes: modes)
            let delta = screen.output(after: full ? nil : previous)
            peer.feed(byteArray: Array(delta.data))
            let actual = TerminalScreen(terminal: peer, modes: modes)
            require(actual.history == screen.history, "Bounded scrollback survives checkpoint and incremental scrolling")
            require(actual.lines == screen.lines, "Mirror must reproduce every cell and attribute")
            require(peer.applicationCursor == host.applicationCursor, "Application cursor mode")
            require(peer.bracketedPasteMode == host.bracketedPasteMode, "Bracketed paste mode")
            require(peer.keyboardEnhancementFlags == host.keyboardEnhancementFlags, "Kitty flags")
            require(peer.buffer.scrollTop == host.buffer.scrollTop && peer.buffer.scrollBottom == host.buffer.scrollBottom, "Scrolling margins")
            require(peer.currentAttribute == host.currentAttribute, "Current attributes")
            require(peer.buffer.x == min(host.cols - 1, host.buffer.x) && peer.buffer.y == host.buffer.y, "Cursor position")
            // Enabling focus reporting emits a synchronous focus notification in SwiftTerm.
            // UIKit suppression is tested separately; no DSR/DA queries are replayed.
            let responses = String(decoding: peerDelegate.replies, as: UTF8.self)
                .replacingOccurrences(of: "\u{1b}[I", with: "").replacingOccurrences(of: "\u{1b}[O", with: "")
            require(responses.isEmpty, "Projection must not replay PTY queries")
            peerDelegate.replies = Data()
            previous = screen
        }
        feed("\u{1b}[?1049h\u{1b}[?1h\u{1b}[?2004h\u{1b}[>3u\u{1b}[2;10r\u{1b}[38;2;12;123;234mHello 世界 👩🏽‍💻\r\nSecond line")
        sync(full: true)
        feed("\r\nThird line\u{1b}[6n\u{1b}[c")
        sync()
        require(!hostDelegate.replies.isEmpty, "The Mac answers PTY queries")
        print("PASS mirror attributes, wide characters, cursor/margins, keyboard modes, sole query responder")

        feed("\u{1b}=\u{1b}[?1004;1006;1000h\u{1b}[?25l")
        sync()
        hostDelegate.replies = Data(); peerDelegate.replies = Data()
        let queries = "\u{1b}[?66$p\u{1b}[?1004$p\u{1b}[?1006$p\u{1b}[?25$p"
        host.feed(text: queries); peer.feed(text: queries)
        require(hostDelegate.replies == peerDelegate.replies, "Keypad, focus, mouse encoding and cursor visibility match the host")
        peerDelegate.replies = Data()
        print("PASS keypad, focus reporting, mouse encoding and cursor visibility")

        feed(String(repeating: "long running output\r\n", count: 20000))
        feed("\u{1b}[2J\u{1b}[5;3H\u{1b}[1;3;4:3;58;5;123mCHECKPOINT")
        feed("\u{1b}[38;2;")
        sync(full: true) // Host parser is halfway through CSI after >256 KiB.
        feed("222;11;22m✓")
        sync()
        let bytes = TerminalScreen(terminal: host, modes: modes).output(after: nil).data
        require(bytes.count < 10000, "Reconnect cost is bounded by screen size, not process lifetime")
        print("PASS full checkpoint after >256 KiB, including split escape sequence")

        feed("\u{1b}[?1049l\u{1b}[r\u{1b}[0m")
        feed(String(repeating: "scrollback\r\n", count: 100))
        feed("LIVE")
        host.buffer.yDisp = 0
        sync(full: true)
        require(previous!.lines.joined().contains("LIVE"), "Mirror follows live screen even when Mac scrolls up")
        feed(String(repeating: "more scrollback\r\n", count: 250))
        sync()
        host.resize(cols: 60, rows: 15)
        peer.resize(cols: 60, rows: 15)
        sync()
        print("PASS alternate-screen exit, independent scroll position and host resize")

        var scanner = TerminalMirrorModes()
        for fragment in ["\u{1b}]0;fake \u{1b}[?66h", "\u{1b}\\", "\u{1b}[?", "66;1006h", "\u{1b}[?25l"] {
            scanner.append(Data(fragment.utf8))
        }
        require(scanner.modes[66] == true && scanner.mouseEncoding == 1006 && scanner.modes[25] == false, "Fragmented mode controls")
        scanner.append(Data("\u{1b}]0;[?66l\u{7}".utf8))
        require(scanner.modes[66] == true, "OSC payload cannot change input modes")
        scanner.append(Data("\u{1b}[!p".utf8))
        require(scanner.modes[66] == false && scanner.modes[25] == true && scanner.mouseEncoding == 1006, "DECSTR semantics")
        scanner.append(Data("\u{1b}c".utf8))
        require(scanner.mouseEncoding == 0 && scanner.modes[66] != true, "RIS semantics")
        print("PASS bounded streaming input-mode scanner")
    }
}
