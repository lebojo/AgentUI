import Foundation

struct CopilotChatDecoder: ChatJournalDecoder {
    private var log = ChatMessageLog()

    var messages: [SessionMessage] { log.messages }

    mutating func consume(_ line: Data, offset: UInt64) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let data = record["data"] as? [String: Any] else { return }
        let id = record["id"] as? String ?? "line:\(offset)"
        switch record["type"] as? String {
        case "user.message":
            log.addText(ChatMessageLog.text(data["content"]), id: id, kind: .input)
        case "assistant.message":
            log.addText(ChatMessageLog.text(data["content"]), id: data["messageId"] as? String ?? id, kind: .assistant)
        case "tool.execution_start":
            guard let call = data["toolCallId"] as? String else { return }
            log.startTool(call, name: data["toolName"] as? String ?? "Outil",
                          detail: ChatMessageLog.summary(of: data["arguments"] as? [String: Any] ?? [:]))
        case "tool.execution_complete":
            guard let call = data["toolCallId"] as? String else { return }
            let result = (data["result"] as? [String: Any])?["content"] as? String
            let error = (data["error"] as? [String: Any])?["message"] as? String
            log.finishTool(call, output: result ?? error ?? "", failed: data["success"] as? Bool == false)
        default: return
        }
        log.trim()
    }

    mutating func consumeOversized(_ head: Data) {
        guard String(decoding: head, as: UTF8.self).contains("\"tool.execution_complete\"") else { return }
        log.finishOversizedTools(in: head, key: "toolCallId")
    }
}
