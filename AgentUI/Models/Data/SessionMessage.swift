import Foundation

enum SessionDisplayMode: String, CaseIterable, Identifiable {
    case chat, terminal
    var id: String { rawValue }
    var title: String { self == .chat ? "Chat" : "Terminal" }
    var symbol: String { self == .chat ? "bubble.left.and.bubble.right" : "terminal" }
}

struct SessionMessage: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case input, output, assistant, tool, notice }
    enum ToolState: String, Codable, Sendable { case running, completed, failed }
    let id: String
    let kind: Kind
    var text: String
    var title: String?
    var toolState: ToolState?

    init(id: String = UUID().uuidString, kind: Kind, text: String, title: String? = nil, toolState: ToolState? = nil) {
        self.id = id
        self.title = title
        self.toolState = toolState
        self.kind = kind
        self.text = text
    }
}

struct SessionTextAppend: Codable, Sendable {
    let id: String
    let text: String
}

struct SessionTranscriptDelta: Sendable {
    let dropped: Int
    let start: Int
    let messages: [SessionMessage]
    let append: SessionTextAppend?

    init(previous: [SessionMessage], current: [SessionMessage]) {
        dropped = current.first.flatMap { first in previous.firstIndex { $0.id == first.id } } ?? previous.count
        let kept = previous.dropFirst(dropped)
        let firstChanged = zip(kept, current).prefix { $0 == $1 }.count
        if kept.count == current.count, firstChanged == current.count - 1,
           let old = kept.last, let new = current.last,
           old.id == new.id, old.kind == new.kind, old.title == new.title, old.toolState == new.toolState, new.text.hasPrefix(old.text) {
            start = current.count
            messages = []
            append = SessionTextAppend(id: new.id, text: String(new.text.dropFirst(old.text.count)))
        } else {
            start = firstChanged
            messages = Array(current.dropFirst(firstChanged))
            append = nil
        }
    }
}

enum SessionChatSource: String, Codable, Sendable {
    case terminal, claude, codex, copilot
}

extension Array where Element == SessionMessage {
    mutating func trimHistory(keepingAtLeast minimum: Int) {
        var bytes = reduce(0) { $0 + $1.text.utf8.count }
        while count > minimum && (count > 200 || bytes > 262_144) {
            bytes -= removeFirst().text.utf8.count
        }
    }
}
