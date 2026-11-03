import Foundation

@main struct ChatJournalTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: message, code: 1) }
    }
    static func record(_ type: String, _ id: String, _ content: Any, meta: Bool = false) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "uuid": id, "isMeta": meta, "message": ["content": content]], options: [.sortedKeys])
        data.append(10)
        return data
    }
    static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
    @MainActor static func eventually(_ description: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: description, code: 1)
    }

    static func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        return data
    }

    static func codexRollout() throws -> [Data] {
        let item = { (payload: [String: Any]) in try line(["type": "response_item", "payload": payload]) }
        return [
            try line(["type": "session_meta", "payload": ["id": "s1", "cwd": "/tmp"]]),
            try item(["type": "message", "role": "developer", "content": [["type": "input_text", "text": "PRIVATE POLICY"]]]),
            try item(["type": "message", "role": "user", "content": [["type": "input_text", "text": "<environment_context>\n<cwd>/tmp</cwd>\n</environment_context>"]]]),
            try item(["type": "message", "role": "user", "id": "u1", "content": [["type": "input_text", "text": "Corrige le bug"]]]),
            try item(["type": "reasoning", "summary": [["type": "summary_text", "text": "PRIVATE"]]]),
            try item(["type": "custom_tool_call", "call_id": "c1", "name": "exec", "input": "ls -la", "status": "completed"]),
            try item(["type": "custom_tool_call_output", "call_id": "c1", "output": [["type": "input_text", "text": "Script completed\nWall time 0.1 seconds\nOutput:\nREADME.md"]]]),
            try item(["type": "function_call", "call_id": "c2", "name": "shell", "arguments": #"{"command":["git","status"]}"#]),
            try item(["type": "function_call_output", "call_id": "c2", "output": #"{"output":"fatal: not a git repository","metadata":{"exit_code":128}}"#]),
            try line(["type": "event_msg", "payload": ["type": "item_completed", "item": ["type": "agent_message", "content": [["text": "DUPLICATE"]]]]]),
            try item(["type": "message", "role": "assistant", "id": "a1", "content": [["type": "output_text", "text": "Terminé."]]])
        ]
    }

    static func codexExecOutputs() throws -> [Data] {
        let item = { (payload: [String: Any]) in try line(["type": "response_item", "payload": payload]) }
        let output = { (call: String, text: String) in try item(["type": "custom_tool_call_output", "call_id": call, "output": [["type": "input_text", "text": text]]]) }
        return [
            try item(["type": "custom_tool_call", "call_id": "r", "name": "exec", "input": "npm run dev"]),
            try output("r", "Script running with cell ID 3\nWall time 1.0 seconds\nOutput:\nready"),
            try item(["type": "custom_tool_call", "call_id": "f", "name": "exec", "input": "false"]),
            try output("f", "Chunk ID: 1\nWall time: 0.0 seconds\nProcess exited with code 1\nOutput:\n"),
            try item(["type": "custom_tool_call", "call_id": "e", "name": "exec", "input": "touch done"]),
            try output("e", "Script completed\nWall time 0.0 seconds\nOutput:\n")
        ]
    }

    static func copilotEvents() throws -> [Data] {
        [
            try line(["type": "session.start", "id": "e0", "data": ["sessionId": "s1"]]),
            try line(["type": "user.message", "id": "e1", "data": ["content": "Ajoute un test"]]),
            try line(["type": "assistant.message", "id": "e2", "data": ["messageId": "m1", "content": "",
                                                                        "toolRequests": [["toolCallId": "t1", "name": "bash"]]]]),
            try line(["type": "tool.execution_start", "id": "e3", "data": ["toolCallId": "t1", "toolName": "bash", "arguments": ["command": "swift test"]]]),
            try line(["type": "tool.execution_complete", "id": "e4", "data": ["toolCallId": "t1", "success": false, "error": ["message": "1 test failed"]]]),
            try line(["type": "assistant.message", "id": "e5", "data": ["messageId": "m2", "content": "Un test échoue."]])
        ]
    }

    @MainActor static func main() async throws {
        var decoder = ClaudeChatDecoder()
        let user = try record("user", "u1", "Bonjour 👋")
        decoder.consume(user, offset: 0)
        decoder.consume(user, offset: 0)
        decoder.consume(try record("user", "meta", "PRIVATE SYSTEM CONTEXT", meta: true), offset: 1)
        decoder.consume(try record("assistant", "a1", [["type": "thinking", "thinking": "PRIVATE"], ["type": "text", "text": "**Bonjour**\n```swift\nlet value = 1\n```"]]), offset: 2)
        decoder.consume(try record("assistant", "a2", [["type": "tool_use", "id": "call-1", "name": "Read", "input": ["file_path": "hello.swift"]]]), offset: 3)
        let before = decoder.messages
        decoder.consume(try record("user", "r1", [["type": "tool_result", "tool_use_id": "call-1", "content": "hello.swift", "is_error": false]], meta: true), offset: 4)
        try require(decoder.messages.count == 3, "User, assistant and tool are distinct; no echo or meta duplicates")
        try require(decoder.messages.last?.toolState == .completed, "Tool results complete the original tool row")
        try require(!decoder.messages.map(\.text).joined().contains("PRIVATE"), "No injected context or private thinking in the UI")
        let delta = SessionTranscriptDelta(previous: before, current: decoder.messages)
        try require(delta.append == nil && delta.messages.last?.toolState == .completed, "Tool metadata updates survive the remote delta even if text is unchanged")
        var notification = try JSONSerialization.data(withJSONObject: ["type": "user", "uuid": "n1", "origin": ["kind": "task-notification"],
                                                                       "message": ["content": "<task-notification><task-id>1</task-id></task-notification>"]])
        notification.append(10)
        decoder.consume(notification, offset: 5)
        decoder.consume(try record("user", "n2", "<task-notification><status>completed</status></task-notification>"), offset: 6)
        try require(decoder.messages.count == 3, "Background task notifications are not shown as user messages")
        print("PASS Claude roles, stable IDs, tool results, meta filtering and remote metadata deltas")

        let sidechain = try line(["type": "user", "uuid": "s1", "isSidechain": true, "agentId": "a1", "message": ["content": "Audit the release workflow"]])
        var session = ClaudeChatDecoder()
        session.consume(sidechain, offset: 0)
        var subagent = ClaudeSubagentChatDecoder()
        subagent.consume(sidechain, offset: 0)
        try require(session.messages.isEmpty && subagent.messages.map(\.text) == ["Audit the release workflow"],
                    "Sidechain records stay out of the session but form the subagent conversation")
        print("PASS Claude subagent journals")

        var codex = CodexChatDecoder()
        for (offset, line) in try codexRollout().enumerated() { codex.consume(line, offset: UInt64(offset)) }
        try require(codex.messages.map(\.kind) == [.input, .tool, .tool, .assistant], "Codex user, tool calls and reply, without injected context or events")
        try require(codex.messages[0].text == "Corrige le bug", "Codex user text")
        try require(codex.messages[1].title == "exec" && codex.messages[1].toolState == .completed && codex.messages[1].text == "README.md",
                    "Codex custom tool output completes its call")
        try require(codex.messages[2].title == "shell" && codex.messages[2].toolState == .failed && codex.messages[2].text == "fatal: not a git repository",
                    "Codex legacy shell output with a non-zero exit code fails its call")
        try require(codex.messages[3].text == "Terminé.", "Codex assistant reply")
        var codexStates = CodexChatDecoder()
        for (offset, record) in try codexExecOutputs().enumerated() { codexStates.consume(record, offset: UInt64(offset)) }
        try require(codexStates.messages.map(\.toolState) == [.running, .failed, .completed],
                    "Codex exec headers report running, non-zero exit and empty output without erasing the command")
        try require(codexStates.messages[2].text == "touch done", "An empty tool output keeps the command visible")
        var codexChunks = CodexChatDecoder()
        let item = { (payload: [String: Any]) in try line(["type": "response_item", "payload": payload]) }
        let chunk = #"{"chunk_id":"a5871d","wall_time_seconds":0.1,"exit_code":1,"original_token_count":3,"output":"No such file"}"#
        for (offset, record) in [
            try item(["type": "custom_tool_call", "call_id": "j", "name": "exec", "input": "cat missing"]),
            try item(["type": "custom_tool_call_output", "call_id": "j", "output": [["type": "input_text", "text": "Script completed\nWall time 0.1 seconds\nOutput:\n"],
                                                                                     ["type": "input_text", "text": "Warning: truncated output\nTotal output lines: 1\n\n" + chunk]]]),
            try item(["type": "message", "role": "user", "id": "html", "content": [["type": "input_text", "text": "<div>hello</div>"]]]),
            try item(["type": "message", "role": "user", "id": "reply", "content": [["type": "input_text", "text": "<send_user_message_question_reply>Oui</send_user_message_question_reply>"]]])
        ].enumerated() { codexChunks.consume(record, offset: UInt64(offset)) }
        try require(codexChunks.messages.first?.toolState == .failed && codexChunks.messages.first?.text == "No such file",
                    "A JSON exec chunk reports its exit code and output")
        try require(codexChunks.messages.dropFirst().map(\.text) == ["<div>hello</div>", "Oui"], "Prompts made of a single element stay visible")
        print("PASS Codex rollout roles, tool calls, legacy shell output and injected context filtering")

        var copilot = CopilotChatDecoder()
        for (offset, line) in try copilotEvents().enumerated() { copilot.consume(line, offset: UInt64(offset)) }
        try require(copilot.messages.map(\.kind) == [.input, .tool, .assistant], "Copilot user, tool and reply; empty tool-request message skipped")
        try require(copilot.messages[1].title == "bash" && copilot.messages[1].toolState == .failed && copilot.messages[1].text == "1 test failed",
                    "Copilot failed tool execution reports its error")
        try require(copilot.messages[2].text == "Un test échoue.", "Copilot assistant reply")
        print("PASS Copilot events, tool executions and replies")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("heka-claude-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("reader.jsonl")
        try Data().write(to: file)
        let reader = ChatJournalReader<ClaudeChatDecoder>()
        try append(user.dropLast(3), to: file)
        let partial = await reader.read(file)
        try require(partial.isEmpty, "A partial record must not become a truncated message")
        try append(user.suffix(3), to: file)
        let complete = await reader.read(file)
        try require(complete.first?.text == "Bonjour 👋", "Split UTF-8 JSON record is reconstructed")
        let unchanged = await reader.read(file)
        try require(unchanged == complete, "Reading an unchanged file emits no duplicate")
        try record("assistant", "replacement", "Replaced").write(to: file, options: .atomic)
        let replacement = await reader.read(file)
        try require(replacement.count == 1 && replacement.first?.text == "Replaced", "Atomic replacement resets reader offsets")
        var huge = Data(repeating: 65, count: 3_000_000); huge.append(10)
        huge.append(try record("assistant", "tail", "Tail survives eviction"))
        try huge.write(to: file, options: .atomic)
        let tail = await reader.read(file)
        try require(tail.count == 1 && tail.first?.text == "Tail survives eviction", "Bounded initial tail skips a partial/oversized record")
        let first = try record("assistant", "boundary", "Boundary first")
        let last = try record("assistant", "boundary-last", "Boundary last")
        var window = first
        window.append(Data(repeating: 120, count: 2_097_152 - first.count - last.count - 1)); window.append(10)
        window.append(last)
        var aligned = Data(repeating: 66, count: 4_096); aligned.append(10)
        aligned.append(window)
        try aligned.write(to: file, options: .atomic)
        let boundary = await ChatJournalReader<ClaudeChatDecoder>().read(file)
        try require(boundary.map(\.text) == ["Boundary first", "Boundary last"], "A tail window starting on a line boundary keeps its first record")
        let oversized = root.appendingPathComponent("oversized.jsonl")
        try item(["type": "custom_tool_call", "call_id": "big", "name": "exec", "input": "screenshot"]).write(to: oversized)
        let oversizedReader = ChatJournalReader<CodexChatDecoder>()
        let started = await oversizedReader.read(oversized)
        try require(started.first?.toolState == .running, "The tool call starts before its result")
        var result = Data(#"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"big","output":""#.utf8)
        result.append(Data(repeating: 65, count: 17_000_000))
        result.append(Data("\"}}\n".utf8))
        result.append(try item(["type": "message", "role": "assistant", "id": "after", "content": [["type": "output_text", "text": "Après"]]]))
        try append(result, to: oversized)
        let finished = await oversizedReader.read(oversized)
        try require(finished.first?.toolState == .completed && finished.last?.text == "Après",
                    "A tool result above the record limit still completes its call and later records are read")
        let long = root.appendingPathComponent("long.jsonl")
        try (0..<250).map { try record("assistant", "long-\($0)", "Message \($0)") }.reduce(Data(), +).write(to: long)
        let bounded = await ChatJournalReader<ClaudeChatDecoder>().read(long)
        try require(bounded.count == 200 && bounded.first?.text == "Message 50" && bounded.last?.text == "Message 249",
                    "A long journal keeps its 200 most recent messages")
        let late = root.appendingPathComponent("late.jsonl")
        var lateRecords = try record("assistant", "early", [["type": "tool_use", "id": "early-call", "name": "Bash", "input": ["command": "sleep 600"]]])
        for index in 0..<250 { lateRecords.append(try record("assistant", "filler-\(index)", "Filler \(index)")) }
        try lateRecords.write(to: late)
        let lateReader = ChatJournalReader<ClaudeChatDecoder>()
        _ = await lateReader.read(late)
        try append(try record("user", "early-result", [["type": "tool_result", "tool_use_id": "early-call", "content": "done"]], meta: true), to: late)
        let afterLate = await lateReader.read(late)
        try require(afterLate.last?.text == "Filler 249" && !afterLate.contains { $0.title == "Tool Result" },
                    "A result for a tool call trimmed from the history is not appended out of context")
        print("PASS incremental reads, partial UTF-8 records, replacement and bounded initial history")

        let log = root.appendingPathComponent("projects/-tmp-project/\(UUID().uuidString).jsonl")
        let transcript = SessionTranscript()
        let monitor = AgentJournalMonitor(transcript: transcript)
        monitor.attach(AgentJournal(source: .claude, url: log))
        try await eventually("A Claude journal attaches before its file exists") { transcript.source == .claude && transcript.messages.isEmpty }
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try user.write(to: log)
        try await eventually("A journal created after attaching is followed") { transcript.messages.count == 1 }
        try append(try record("assistant", "live", "Live without any PTY output"), to: log)
        try await eventually("Appended records update Chat") { transcript.messages.last?.text == "Live without any PTY output" }
        try append(try record("assistant", "again", "Second append"), to: log)
        try await eventually("The watch survives appends") { transcript.messages.last?.text == "Second append" }
        try record("assistant", "replaced", "Replaced").write(to: log, options: .atomic)
        try await eventually("An atomic replacement is followed") { transcript.messages.last?.text == "Replaced" }
        try append(try record("assistant", "after", "After replacement"), to: log)
        try await eventually("The watch follows the replacement file") { transcript.messages.last?.text == "After replacement" }
        monitor.suspend()
        try append(try record("assistant", "suspended", "While suspended"), to: log)
        try require(transcript.messages.last?.text == "After replacement", "A suspended journal keeps its messages")
        monitor.attach(AgentJournal(source: .claude, url: log))
        try require(transcript.messages.last?.text == "After replacement", "Reattaching keeps the chat until the journal is read")
        try await eventually("Reattaching reads what was appended while suspended") { transcript.messages.last?.text == "While suspended" }
        monitor.attach(nil)
        try require(transcript.source == .terminal, "Detaching the Claude journal returns to the terminal transcript")
        print("PASS Claude journal monitor follows creation, appends and replacement")

        let rollout = root.appendingPathComponent("rollout-2026-10-30T10-00-00-00000000-0000-0000-0000-000000000000.jsonl")
        let lines = try codexRollout()
        try lines.prefix(4).reduce(Data(), +).write(to: rollout)
        let codexTranscript = SessionTranscript()
        let journalMonitor = AgentJournalMonitor(transcript: codexTranscript)
        journalMonitor.attach(AgentJournal(source: .codex, url: rollout))
        try await eventually("Codex journal attaches") { codexTranscript.source == .codex && codexTranscript.messages.count == 1 }
        try append(lines.dropFirst(4).reduce(Data(), +), to: rollout)
        try await eventually("Codex journal follows appended records") { codexTranscript.messages.last?.text == "Terminé." }
        journalMonitor.attach(nil)
        try require(codexTranscript.source == .terminal, "Detaching the agent journal returns to the terminal transcript")
        print("PASS Codex journal monitor follows the live rollout and detaches")
    }
}
