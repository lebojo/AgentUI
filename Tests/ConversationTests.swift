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

        let index = ConversationIndex(home: home)
        let conversations = await index.conversations(at: path)
        let titles = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0.title) })
        try require(titles == [
            "claude:titled": "Login bug fix",
            "claude:untitled": "Write the tests",
            "codex:thread": "Refactor the sidebar",
            "codex:indexed": "Build the agent bar"
        ], "Conversations are filtered by cwd and titled, got \(titles)")
        try require(await index.conversations(at: path.uppercased()).count == 4, "Paths match on case-insensitive volumes")
        try require(conversations.map(\.updatedAt) == conversations.map(\.updatedAt).sorted(by: >), "Most recent conversations come first")
        try require(conversations.first { $0.id == "claude:titled" }?.resumeCommand == ["claude", "--resume", "titled"], "Claude resume command")
        try require(conversations.first { $0.id == "codex:thread" }?.resumeCommand == ["codex", "resume", "thread"], "Codex resume command")

        try write(claude.appendingPathComponent("untitled.jsonl"), [
            #"{"type":"user","cwd":"\#(path)","message":{"role":"user","content":"Write the tests"}}"#,
            #"{"type":"custom-title","customTitle":"Renamed session"}"#
        ])
        let renamed = await index.conversations(at: path)
        try require(renamed.first { $0.id == "claude:untitled" }?.title == "Renamed session", "A changed transcript is read again")
        try require(await index.conversations(at: other.path).map(\.id) == ["codex:other"], "Encoded directory alone does not match another cwd")
        print("PASS conversation index")
    }

    private static func write(_ url: URL, _ lines: [String], partialLastLine: Bool = false) throws {
        let text = lines.joined(separator: "\n") + (partialLastLine ? "" : "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
