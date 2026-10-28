import Foundation

enum JSONLines {
    static func forEach(_ url: URL, limit: Int, _ body: (Data) -> Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var buffer = Data()
        var read = 0
        while read < limit {
            guard let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty else {
                if !buffer.isEmpty { _ = body(buffer) }
                return
            }
            read += chunk.count
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0A) {
                let line = Data(buffer[start..<newline])
                start = buffer.index(after: newline)
                if !line.isEmpty, !body(line) { return }
            }
            buffer = Data(buffer[start...])
        }
    }

    static func line(_ line: Data, contains marker: String) -> Bool {
        line.range(of: Data(marker.utf8)) != nil
    }
}

enum ConversationTitle {
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty, !words.hasPrefix("<") else { return nil }
        return words.count > 120 ? String(words.prefix(119)) + "…" : words
    }
}

struct MessageContent: Decodable {
    let text: String?

    private struct Block: Decodable {
        let type: String?
        let text: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.text = text
        } else {
            let blocks = (try? container.decode([Block].self)) ?? []
            text = blocks.first { $0.type == "text" || $0.type == "input_text" }?.text
        }
    }
}

struct ClaudeTranscript: Equatable, Sendable {
    var cwd: String?
    var customTitle: String?
    var aiTitle: String?
    var firstPrompt: String?

    var title: String? { customTitle ?? aiTitle ?? firstPrompt }
    private var isComplete: Bool { cwd != nil && (customTitle != nil || aiTitle != nil) }

    private struct Line: Decodable {
        let type: String?
        let cwd: String?
        let aiTitle: String?
        let customTitle: String?
        let isMeta: Bool?
        let message: Message?
    }

    private struct Message: Decodable {
        let content: MessageContent?
    }

    static func read(_ url: URL, limit: Int = 8_388_608) -> ClaudeTranscript {
        var transcript = ClaudeTranscript()
        JSONLines.forEach(url, limit: limit) { line in
            transcript.consume(line)
            return !transcript.isComplete
        }
        return transcript
    }

    private mutating func consume(_ data: Data) {
        let wanted = JSONLines.line(data, contains: "\"ai-title\"") || JSONLines.line(data, contains: "\"custom-title\"")
            || (cwd == nil && JSONLines.line(data, contains: "\"cwd\""))
            || (firstPrompt == nil && JSONLines.line(data, contains: "\"type\":\"user\""))
        guard wanted, let line = try? JSONDecoder().decode(Line.self, from: data) else { return }
        if cwd == nil { cwd = line.cwd }
        switch line.type {
        case "ai-title": aiTitle = ConversationTitle.clean(line.aiTitle) ?? aiTitle
        case "custom-title": customTitle = ConversationTitle.clean(line.customTitle) ?? customTitle
        case "user" where firstPrompt == nil && line.isMeta != true:
            firstPrompt = ConversationTitle.clean(line.message?.content?.text)
        default: break
        }
    }
}

struct CodexRollout: Equatable, Sendable {
    let sessionID: String
    let cwd: String
    let firstPrompt: String?

    private struct Header: Decodable {
        let type: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let id: String
        let sessionID: String?
        let cwd: String

        enum CodingKeys: String, CodingKey {
            case id, cwd
            case sessionID = "session_id"
        }
    }

    private struct Item: Decodable {
        let type: String?
        let payload: ItemPayload?
    }

    private struct ItemPayload: Decodable {
        let type: String?
        let role: String?
        let content: MessageContent?
    }

    static func read(_ url: URL, limit: Int = 2_097_152) -> CodexRollout? {
        var header: Payload?
        var prompt: String?
        JSONLines.forEach(url, limit: limit) { line in
            guard header != nil else {
                guard let decoded = try? JSONDecoder().decode(Header.self, from: line), decoded.type == "session_meta",
                      (decoded.payload.sessionID ?? decoded.payload.id) == decoded.payload.id else { return false }
                header = decoded.payload
                return true
            }
            guard JSONLines.line(line, contains: "\"role\":\"user\""),
                  let item = try? JSONDecoder().decode(Item.self, from: line),
                  item.type == "response_item", item.payload?.type == "message", item.payload?.role == "user",
                  let text = item.payload?.content?.text, !text.hasPrefix("# AGENTS.md") else { return true }
            prompt = ConversationTitle.clean(text)
            return prompt == nil
        }
        guard let header else { return nil }
        return CodexRollout(sessionID: header.id, cwd: header.cwd, firstPrompt: prompt)
    }

    static func titles(in index: URL) -> [String: String] {
        struct Entry: Decodable {
            let id: String
            let threadName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case threadName = "thread_name"
            }
        }
        var titles: [String: String] = [:]
        JSONLines.forEach(index, limit: 16_777_216) { line in
            if let entry = try? JSONDecoder().decode(Entry.self, from: line), let title = ConversationTitle.clean(entry.threadName) {
                titles[entry.id] = title
            }
            return true
        }
        return titles
    }
}
