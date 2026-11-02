import Foundation

struct ClaudeChatDecoder: ChatJournalDecoder {
    private let includesSidechains: Bool
    private var log = ChatMessageLog()

    init() { includesSidechains = false }

    init(includesSidechains: Bool) { self.includesSidechains = includesSidechains }

    var messages: [SessionMessage] { log.messages }

    mutating func trim() { log.trim() }

    mutating func consume(_ line: Data, offset: UInt64) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              includesSidechains || record["isSidechain"] as? Bool != true else { return }
        let role = record["type"] as? String
        guard role == "user" || role == "assistant", let message = record["message"] as? [String: Any] else { return }
        let origin = (record["origin"] as? [String: Any])?["kind"] as? String
        let isMeta = record["isMeta"] as? Bool == true || record["isSynthetic"] as? Bool == true || record["isCompactSummary"] as? Bool == true
            || (role == "user" && origin.map { $0 != "human" } == true)
        let id = record["uuid"] as? String ?? "line:\(offset)"
        let kind: SessionMessage.Kind = role == "user" ? .input : .assistant
        if let text = message["content"] as? String {
            if !isMeta { addText(text, id: id, kind: kind) }
        } else if let blocks = message["content"] as? [[String: Any]] {
            for (index, block) in blocks.enumerated() {
                switch block["type"] as? String {
                case "text" where !isMeta:
                    if let text = block["text"] as? String { addText(text, id: "\(id):\(index)", kind: kind) }
                case "tool_use":
                    guard let call = block["id"] as? String else { continue }
                    log.startTool(call, name: block["name"] as? String ?? String(localized: "Tool"),
                                  detail: ChatMessageLog.summary(of: block["input"] as? [String: Any] ?? [:]))
                case "tool_result":
                    guard let call = block["tool_use_id"] as? String else { continue }
                    log.finishTool(call, output: ChatMessageLog.text(block["content"]), failed: block["is_error"] as? Bool == true)
                default: break
                }
            }
        }
    }

    mutating func consumeOversized(_ head: Data) {
        log.finishOversizedTools(in: head, key: "tool_use_id")
    }

    private mutating func addText(_ text: String, id: String, kind: SessionMessage.Kind) {
        guard !Self.isTerminalMarkup(text) else { return }
        log.addText(text, id: id, kind: kind)
    }

    private static func isTerminalMarkup(_ text: String) -> Bool {
        ["<local-command-", "<command-name>", "<system-reminder>", "<task-notification>"].contains { text.hasPrefix($0) }
    }
}

struct ClaudeSubagentChatDecoder: ChatJournalDecoder {
    private var decoder = ClaudeChatDecoder(includesSidechains: true)

    var messages: [SessionMessage] { decoder.messages }

    mutating func trim() { decoder.trim() }

    mutating func consume(_ line: Data, offset: UInt64) { decoder.consume(line, offset: offset) }

    mutating func consumeOversized(_ head: Data) { decoder.consumeOversized(head) }
}
