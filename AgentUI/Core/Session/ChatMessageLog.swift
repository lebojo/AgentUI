import Foundation

protocol ChatJournalDecoder: Sendable {
    init()
    var messages: [SessionMessage] { get }
    mutating func consume(_ line: Data, offset: UInt64)
}

struct ChatMessageLog: Sendable {
    private(set) var messages: [SessionMessage] = []

    mutating func upsert(_ message: SessionMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
        else { messages.append(message) }
    }

    mutating func addText(_ text: String, id: String, kind: SessionMessage.Kind) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        upsert(SessionMessage(id: id, kind: kind, text: Self.bounded(text)))
    }

    mutating func startTool(_ call: String, name: String, detail: String) {
        upsert(SessionMessage(id: "tool:\(call)", kind: .tool, text: Self.bounded(detail), title: name, toolState: .running))
    }

    mutating func finishTool(_ call: String, output: String, failed: Bool) {
        finishTool(call, output: output, state: failed ? .failed : .completed)
    }

    mutating func finishTool(_ call: String, output: String, state: SessionMessage.ToolState) {
        let id = "tool:\(call)"
        let hasOutput = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let index = messages.firstIndex(where: { $0.id == id }) {
            if hasOutput { messages[index].text = Self.bounded(output) }
            messages[index].toolState = state
        } else {
            upsert(SessionMessage(id: id, kind: .tool, text: Self.bounded(output), title: "Résultat de l’outil", toolState: state))
        }
    }

    mutating func trim() {
        var bytes = messages.reduce(0) { $0 + $1.text.utf8.count }
        while messages.count > 1 && (messages.count > 200 || bytes > 262_144) {
            bytes -= messages.removeFirst().text.utf8.count
        }
    }

    static func bounded(_ text: String) -> String {
        guard text.utf8.count > 65_536 else { return text }
        return String(decoding: text.utf8.prefix(65_500), as: UTF8.self) + "\n… (contenu tronqué)"
    }

    static func json(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func text(_ value: Any?) -> String {
        if let text = value as? String { return text }
        return (value as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
    }

    static func summary(of arguments: [String: Any]) -> String {
        if let command = arguments["command"] as? [String] { return command.joined(separator: " ") }
        return arguments["command"] as? String ?? arguments["cmd"] as? String ?? arguments["file_path"] as? String
            ?? arguments["pattern"] as? String ?? arguments["path"] as? String ?? json(arguments)
    }
}
