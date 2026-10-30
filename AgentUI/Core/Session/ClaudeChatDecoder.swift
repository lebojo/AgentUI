import Foundation

struct ClaudeChatDecoder: ChatJournalDecoder {
    private var log = ChatMessageLog()

    var messages: [SessionMessage] { log.messages }

    mutating func consume(_ line: Data, offset: UInt64) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              record["isSidechain"] as? Bool != true else { return }
        let role = record["type"] as? String
        guard role == "user" || role == "assistant", let message = record["message"] as? [String: Any] else { return }
        let isMeta = record["isMeta"] as? Bool == true || record["isSynthetic"] as? Bool == true || record["isCompactSummary"] as? Bool == true
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
                    log.startTool(call, name: block["name"] as? String ?? "Outil",
                                  detail: ChatMessageLog.summary(of: block["input"] as? [String: Any] ?? [:]))
                case "tool_result":
                    guard let call = block["tool_use_id"] as? String else { continue }
                    log.finishTool(call, output: ChatMessageLog.text(block["content"]), failed: block["is_error"] as? Bool == true)
                default: break
                }
            }
        }
        log.trim()
    }

    private mutating func addText(_ text: String, id: String, kind: SessionMessage.Kind) {
        guard !Self.isTerminalMarkup(text) else { return }
        log.addText(text, id: id, kind: kind)
    }

    private static func isTerminalMarkup(_ text: String) -> Bool {
        text.hasPrefix("<local-command-") || text.hasPrefix("<command-name>") || text.hasPrefix("<system-reminder>")
    }
}
