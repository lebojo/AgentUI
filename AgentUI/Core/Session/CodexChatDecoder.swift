import Foundation

struct CodexChatDecoder: ChatJournalDecoder {
    private static let injectedContextPrefixes = ["# AGENTS.md instructions"]
    private static let injectedContextTags = ["environment_context", "user_instructions", "turn_aborted", "subagent_notification",
                                              "permissions instructions", "apps_instructions", "skills_instructions", "collaboration_mode", "image"]
    private static let userReplyTag = "send_user_message_question_reply"

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

    mutating func consumeOversized(_ head: Data) {
        guard String(decoding: head, as: UTF8.self).contains("_call_output\"") else { return }
        log.finishOversizedTools(in: head, key: "call_id")
    }

    private mutating func addMessage(_ item: [String: Any], id: String) {
        let text = ChatMessageLog.text(item["content"])
        switch item["role"] as? String {
        case "assistant": log.addText(text, id: id, kind: .assistant)
        case "user" where !Self.isInjectedContext(text): log.addText(Self.unwrappedReply(text), id: id, kind: .input)
        default: break
        }
    }

    private static func isInjectedContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if injectedContextPrefixes.contains(where: trimmed.hasPrefix) { return true }
        return injectedContextTags.contains { trimmed.hasPrefix("<\($0)>") && trimmed.hasSuffix("</\($0.split(separator: " ")[0])>") }
    }

    private static func unwrappedReply(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = "<\(userReplyTag)>", closing = "</\(userReplyTag)>"
        guard trimmed.hasPrefix(opening), trimmed.hasSuffix(closing), trimmed.count >= opening.count + closing.count else { return text }
        return String(trimmed.dropFirst(opening.count).dropLast(closing.count)).trimmingCharacters(in: .whitespacesAndNewlines)
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
        let raw = String(text[marker.upperBound...])
        let chunks = execChunks(raw)
        let body = chunks?.text ?? raw
        if header.first?.hasPrefix("Script running") == true { return (body, .running) }
        let failed = chunks?.failed == true
            || header.contains { $0.hasPrefix("Process exited with code ") && !$0.hasSuffix(" 0") }
            || header.first?.localizedCaseInsensitiveContains("failed") == true
        return (body, failed ? .failed : .completed)
    }

    private static func execChunks(_ body: String) -> (text: String, failed: Bool)? {
        let chunks = body.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard line.hasPrefix("{"), let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  object["chunk_id"] != nil else { return nil }
            return object
        }
        guard !chunks.isEmpty else { return nil }
        return (chunks.compactMap { $0["output"] as? String }.joined(),
                chunks.contains { ($0["exit_code"] as? Int).map { $0 != 0 } == true })
    }
}
