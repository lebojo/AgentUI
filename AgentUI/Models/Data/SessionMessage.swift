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
    let keeping: Int
    let text: String

    func applied(to previous: String) -> String? {
        guard keeping <= previous.utf8.count else { return nil }
        return String(decoding: previous.utf8.prefix(keeping), as: UTF8.self) + text
    }
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
           old.id == new.id, old.kind == new.kind, old.title == new.title, old.toolState == new.toolState,
           case let shared = zip(old.text, new.text).prefix(while: { $0 == $1 }).count, shared > 0 {
            let oldEnd = old.text.index(old.text.startIndex, offsetBy: shared)
            let newEnd = new.text.index(new.text.startIndex, offsetBy: shared)
            start = current.count
            messages = []
            append = SessionTextAppend(id: new.id, keeping: old.text.utf8.distance(from: old.text.startIndex, to: oldEnd),
                                       text: String(new.text[newEnd...]))
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
        var dropped = 0
        while count - dropped > minimum && (count - dropped > 200 || bytes > 262_144) {
            bytes -= self[dropped].text.utf8.count
            dropped += 1
        }
        removeFirst(dropped)
    }
}
