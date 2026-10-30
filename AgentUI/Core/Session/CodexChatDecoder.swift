import Foundation

struct CodexChatDecoder: ChatJournalDecoder {
    private static let injectedContextPrefixes = ["# AGENTS.md instructions"]

    private var log = ChatMessageLog()

    var messages: [SessionMessage] { log.messages }

    mutating func consume(_ line: Data, offset: UInt64) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              record["type"] as? String == "response_item", let item = record["payload"] as? [String: Any] else { return }
        let id = item["id"] as? String ?? "line:\(offset)"
        switch item["type"] as? String {
        case "message": addMessage(item, id: id)
        case "function_call", "custom_tool_call", "local_shell_call":
            log.startTool(item["call_id"] as? String ?? id, name: item["name"] as? String ?? "shell", detail: Self.detail(of: item))
        case "function_call_output", "custom_tool_call_output":
            guard let call = item["call_id"] as? String else { return }
            let result = Self.result(item["output"])
            log.finishTool(call, output: result.text, state: result.state)
        default: return
        }
        log.trim()
    }

    private mutating func addMessage(_ item: [String: Any], id: String) {
        let text = ChatMessageLog.text(item["content"])
        switch item["role"] as? String {
        case "assistant": log.addText(text, id: id, kind: .assistant)
        case "user" where !Self.isInjectedContext(text): log.addText(text, id: id, kind: .input)
        default: break
        }
    }

    private static func isInjectedContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if injectedContextPrefixes.contains(where: trimmed.hasPrefix) { return true }
        guard trimmed.hasPrefix("<"), let end = trimmed.firstIndex(of: ">") else { return false }
        let tag = trimmed[trimmed.index(after: trimmed.startIndex)..<end]
        return !tag.isEmpty && !tag.contains(" ") && trimmed.hasSuffix("</\(tag)>")
    }

    private static func detail(of item: [String: Any]) -> String {
        if let input = item["input"] as? String { return input }
        if let command = (item["action"] as? [String: Any])?["command"] as? [String] { return command.joined(separator: " ") }
        guard let arguments = item["arguments"] as? String else { return "" }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] else { return arguments }
        return ChatMessageLog.summary(of: object)
    }

    private static func result(_ output: Any?) -> (text: String, state: SessionMessage.ToolState) {
        guard let text = output as? String else { return execResult(ChatMessageLog.text(output)) }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let wrapped = object["output"] as? String else { return execResult(text) }
        let exitCode = (object["metadata"] as? [String: Any])?["exit_code"] as? Int
        return (wrapped, exitCode.map { $0 != 0 } == true ? .failed : .completed)
    }

    private static func execResult(_ text: String) -> (text: String, state: SessionMessage.ToolState) {
        guard let marker = text.range(of: "Output:\n"), marker.lowerBound == text.startIndex || text[text.index(before: marker.lowerBound)] == "\n" else {
            return (text, .completed)
        }
        let header = text[..<marker.lowerBound].split(whereSeparator: \.isNewline)
        let body = String(text[marker.upperBound...])
        if header.first?.hasPrefix("Script running") == true { return (body, .running) }
        let failed = header.contains { $0.hasPrefix("Process exited with code ") && !$0.hasSuffix(" 0") }
            || header.first?.localizedCaseInsensitiveContains("failed") == true
        return (body, failed ? .failed : .completed)
    }
}
