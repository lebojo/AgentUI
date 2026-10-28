import Foundation

struct Failure: Error {
    let message: String
}

@main
enum ConversationTests {
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func main() async throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("agentui-conversations-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("My Project.v2", isDirectory: true)
        let other = home.appendingPathComponent("Other", isDirectory: true)
        let accented = home.appendingPathComponent("Développement", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let path = project.path

        try require(ConversationIndex.claudeDirectoryName(for: "/Users/me/My Project.v2") == "-Users-me-My-Project-v2", "Claude directory encoding")

        let claude = home.appendingPathComponent(".claude/projects/\(ConversationIndex.claudeDirectoryName(for: path))", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try write(claude.appendingPathComponent("titled.jsonl"), [
            #"{"type":"last-prompt","sessionId":"titled"}"#,
            #"{"type":"user","isMeta":true,"cwd":"\#(path)","message":{"role":"user","content":"<command-name>/init</command-name>"}}"#,
            #"{"type":"user","cwd":"\#(path)","message":{"role":"user","content":[{"type":"text","text":"Fix the\n  login bug"}]}}"#,
            #"{"type":"ai-title","aiTitle":"Login bug fix","sessionId":"titled"}"#
        ])
        try write(claude.appendingPathComponent("untitled.jsonl"), [
            #"{"type":"user","cwd":"\#(path)","message":{"role":"user","content":"Write the tests"}}"#
        ], partialLastLine: true)
        try write(claude.appendingPathComponent("empty.jsonl"), [
            #"{"type":"attachment","cwd":"\#(path)"}"#
        ])
        try write(claude.appendingPathComponent("collision.jsonl"), [
            #"{"type":"user","cwd":"\#(other.path)","message":{"role":"user","content":"Elsewhere"}}"#
        ])

        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        let day = codex.appendingPathComponent("sessions/2026/10/28", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try write(day.appendingPathComponent("rollout-1-thread.jsonl"), [
            #"{"type":"session_meta","payload":{"id":"thread","session_id":"thread","cwd":"\#(path)","source":"cli"}}"#,
            ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions"}]}}"##,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Refactor the sidebar"}]}}"#
        ])
        try write(day.appendingPathComponent("rollout-2-indexed.jsonl"), [
            #"{"type":"session_meta","payload":{"id":"indexed","cwd":"\#(path)","source":"vscode"}}"#
        ])
        try write(day.appendingPathComponent("rollout-3-child.jsonl"), [
            #"{"type":"session_meta","payload":{"id":"child","session_id":"thread","cwd":"\#(path)","source":{"subagent":{}}}}"#
        ])
        try write(day.appendingPathComponent("rollout-4-other.jsonl"), [
            #"{"type":"session_meta","payload":{"id":"other","cwd":"\#(other.path)","source":"cli"}}"#
        ])
        try write(codex.appendingPathComponent("session_index.jsonl"), [
            #"{"id":"indexed","thread_name":"Old name"}"#,
            #"{"id":"indexed","thread_name":"Build the agent bar"}"#
        ])

        let copilot = home.appendingPathComponent(".copilot/session-state", isDirectory: true)
        try writeCopilot(copilot.appendingPathComponent("named"), [
            "id: named",
            "cwd: '\(path)'",
            "name: \"Ship the \\\"usage\\\" bar\"",
            "summary: |-",
            "  Long summary",
            "  on two lines"
        ], events: [])
        try writeCopilot(copilot.appendingPathComponent("summarized"), [
            "cwd: \(path)",
            "summary: |-",
            "  Add Copilot",
            "  support"
        ], events: [])
        try writeCopilot(copilot.appendingPathComponent("prompted"), ["cwd: \(path)"], events: [
            #"{"type":"session.start","data":{"sessionId":"prompted","context":{"cwd":"\#(path)"}}}"#,
            #"{"type":"user.message","data":{"content":"Fix the\nterminal resize"}}"#
        ])
        try writeCopilot(copilot.appendingPathComponent("blank"), ["cwd: \(path)"], events: [
            #"{"type":"session.start","data":{"sessionId":"blank"}}"#
        ])
        try FileManager.default.createDirectory(at: copilot.appendingPathComponent("windows"), withIntermediateDirectories: true)
        try "cwd: \(path)  # worktree\r\nsummary: Windows line endings # generated\r\nrepository:\r\n- url: https://example.com\r\n"
            .write(to: copilot.appendingPathComponent("windows/workspace.yaml"), atomically: true, encoding: .utf8)
        try writeCopilot(copilot.appendingPathComponent("elsewhere"), ["cwd: \(other.path)", "summary: Elsewhere"], events: [])

        let openCode = home.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: openCode, withIntermediateDirectories: true)
        try sqlite(openCode.appendingPathComponent("opencode.db"), """
            CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL, title TEXT NOT NULL,
                                  time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, time_archived INTEGER);
            INSERT INTO session VALUES ('ses_root', NULL, '\(path)', 'Polish the inspector', 1, 1798000000000, NULL);
            INSERT INTO session VALUES ('ses_child', 'ses_root', '\(path)', 'Subagent task', 1, 1798000000000, NULL);
            INSERT INTO session VALUES ('ses_archived', NULL, '\(path)', 'Archived', 1, 1798000000000, 1798000000001);
            INSERT INTO session VALUES ('ses_other', NULL, '\(other.path)', 'Elsewhere', 1, 1798000000000, NULL);
            INSERT INTO session VALUES ('ses_accent', NULL, '\(accented.path.uppercased())', 'Accented', 1, 1798000000000, NULL);
            CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL, time_updated INTEGER NOT NULL);
            INSERT INTO session_v2 VALUES ('ses_v2', '\(path)', 1797000000000);
            """)

        let index = ConversationIndex(home: home)
        let conversations = await index.conversations(at: path)
        let titles = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0.title) })
        try require(titles == [
            "claude:titled": "Login bug fix",
            "claude:untitled": "Write the tests",
            "codex:thread": "Refactor the sidebar",
            "codex:indexed": "Build the agent bar",
            "copilot:named": "Ship the \"usage\" bar",
            "copilot:summarized": "Add Copilot support",
            "copilot:prompted": "Fix the terminal resize",
            "copilot:blank": "Conversation Copilot",
            "copilot:windows": "Windows line endings",
            "opencode:ses_root": "Polish the inspector",
            "opencode:ses_v2": "Conversation OpenCode"
        ], "Conversations are filtered by cwd and titled, got \(titles)")
        try require(await index.conversations(at: path.uppercased()).count == 11, "Paths match on case-insensitive volumes")
        try require(conversations.map(\.updatedAt) == conversations.map(\.updatedAt).sorted(by: >), "Most recent conversations come first")
        try require(conversations.first { $0.id == "claude:titled" }?.resumeCommand == ["claude", "--resume", "titled"], "Claude resume command")
        try require(conversations.first { $0.id == "codex:thread" }?.resumeCommand == ["codex", "resume", "thread"], "Codex resume command")
        try require(conversations.first { $0.id == "copilot:named" }?.resumeCommand == ["copilot", "--resume", "named"], "Copilot resume command")
        try require(conversations.first { $0.id == "opencode:ses_root" }?.resumeCommand == ["opencode", "--session", "ses_root"], "OpenCode resume command")
        try require(conversations.first { $0.id == "opencode:ses_root" }?.updatedAt == Date(timeIntervalSince1970: 1_798_000_000), "OpenCode times are in milliseconds")

        try write(claude.appendingPathComponent("untitled.jsonl"), [
            #"{"type":"user","cwd":"\#(path)","message":{"role":"user","content":"Write the tests"}}"#,
            #"{"type":"custom-title","customTitle":"Renamed session"}"#
        ])
        let renamed = await index.conversations(at: path)
        try require(renamed.first { $0.id == "claude:untitled" }?.title == "Renamed session", "A changed transcript is read again")
        let elsewhere = await index.conversations(at: other.path).map(\.id).sorted()
        try require(elsewhere == ["codex:other", "copilot:elsewhere", "opencode:ses_other"], "Encoded directory alone does not match another cwd, got \(elsewhere)")
        try require(await index.conversations(at: accented.path).map(\.id) == ["opencode:ses_accent"], "OpenCode paths match case-insensitively beyond ASCII")
        try sqlite(openCode.appendingPathComponent("opencode.db"), """
            INSERT INTO session VALUES ('ses_new', NULL, '\(path)', 'Fresh session', 1, 1799000000000, NULL);
            """)
        try require(await index.conversations(at: path).first?.id == "opencode:ses_new", "A changed OpenCode database is read again")
        print("PASS conversation index")
    }

    private static func writeCopilot(_ directory: URL, _ workspace: [String], events: [String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(directory.appendingPathComponent("workspace.yaml"), workspace)
        if !events.isEmpty { try write(directory.appendingPathComponent("events.jsonl"), events) }
    }

    private static func sqlite(_ database: URL, _ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, script]
        try process.run()
        process.waitUntilExit()
        try require(process.terminationStatus == 0, "sqlite3 fixture")
    }

    private static func write(_ url: URL, _ lines: [String], partialLastLine: Bool = false) throws {
        let text = lines.joined(separator: "\n") + (partialLastLine ? "" : "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
