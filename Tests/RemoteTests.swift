import Foundation

@main struct RemoteTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw RemoteError(message: "FAIL: " + message) }
    }

    @MainActor static func main() throws {
        for address in ["192.168.1.42", "10.0.0.1", "172.16.0.1", "172.31.255.254", "127.0.0.1", "::1", "fd00::1", " 192.168.0.1\n"] {
            _ = try RemoteProtocol.host(address)
        }
        for address in ["", "8.8.8.8", "172.32.0.1", "192.169.1.1", "https://192.168.1.1", "mac.local", "192.168.1.1:80", "2001:4860:4860::8888"] {
            do {
                _ = try RemoteProtocol.host(address)
                throw RemoteError(message: "FAIL: accepted " + address)
            } catch let error as RemoteError {
                try require(!error.message.hasPrefix("FAIL:"), error.message)
            }
        }
        print("PASS literal LAN address validation")

        let transcript = SessionTranscript()
        transcript.update(screen: "Welcome\0\n$ ")
        try require(transcript.messages.last?.text.contains("\0") == false, "Remove wide-character terminal padding from accessible chat text")
        transcript.sent("pwd")
        transcript.update(screen: "Welcome\n$ pwd\n/project\n$ ")
        try require(transcript.messages.count == 3, "Chat retains input and the initial output separately")
        try require(transcript.messages.last?.text.contains("/project") == true, "Chat contains process output")
        let prompt = SessionTranscript()
        prompt.update(screen: "╰─＞")
        prompt.sent("ls")
        prompt.update(screen: "╰─＞ ls\nREADME.md\n╰─＞")
        try require(prompt.messages.last?.text.contains("README.md") == true, "A repeated prompt does not hide the output")
        let scrollback = (0..<3_000).map { "line \($0) of a long session" }.joined(separator: "\n")
        transcript.update(screen: scrollback + "\n$ ")
        transcript.sent("ls")
        transcript.update(screen: String(scrollback.dropFirst(500)) + "\n$ ls\nREADME.md\n$ ")
        try require(transcript.messages.last?.text == "ls\nREADME.md\n$ ", "A sliding scrollback window still isolates the new output")
        let outputID = transcript.messages.last?.id
        transcript.update(screen: "A full-screen tool redrew its output")
        try require(transcript.messages.last?.id == outputID, "Redraw updates the current bubble without adding history")
        for _ in 0..<150 {
            transcript.sent("continue")
            transcript.update(screen: String(repeating: "x", count: 40_000) + UUID().uuidString)
        }
        try require(transcript.messages.count <= 100, "Message count is bounded")
        try require(transcript.messages.reduce(0) { $0 + $1.text.utf8.count } <= 262_144, "Chat memory is bounded")
        let repetitive = SessionTranscript()
        repetitive.update(screen: String(repeating: "x", count: 40_000))
        repetitive.sent("go")
        let clock = ContinuousClock()
        let elapsed = clock.measure { repetitive.update(screen: String(repeating: "x", count: 40_001)) }
        try require(elapsed < .milliseconds(100), "Finding the sent anchor in repetitive output stays fast")
        print("PASS shared chat transcript and redraw handling")

        let old = SessionMessage(kind: .output, text: String(repeating: "a", count: 50_000))
        var grown = old
        grown.text += "next token"
        let incremental = SessionTranscriptDelta(previous: [old], current: [grown])
        try require(incremental.messages.isEmpty && incremental.append?.text == "next token", "Stream only appended text, not the entire growing bubble")
        var spinner = old
        spinner.text += "⠋"
        var spun = old
        spun.text += "⠙ done"
        let spinning = SessionTranscriptDelta(previous: [spinner], current: [spun])
        try require(spinning.messages.isEmpty && spinning.append?.text == "⠙ done" && spinning.append?.applied(to: spinner.text) == spun.text,
                    "A redraw near the end only sends the changed tail")
        grown.text = "redrawn screen"
        let redraw = SessionTranscriptDelta(previous: [old], current: [grown])
        try require(redraw.append == nil && redraw.messages.first?.text == "redrawn screen", "Redraw replaces changed output")
        let history = (0..<5).map { SessionMessage(id: "m\($0)", kind: .assistant, text: "\($0)") }
        let trimmed = Array(history.dropFirst(2)) + [SessionMessage(id: "m5", kind: .assistant, text: "5")]
        let shifted = SessionTranscriptDelta(previous: history, current: trimmed)
        try require(shifted.dropped == 2 && shifted.start == 3 && shifted.messages.map(\.id) == ["m5"],
                    "A transcript trimmed from the front only sends the new message")
        let replaced = SessionTranscriptDelta(previous: history, current: [SessionMessage(id: "other", kind: .notice, text: "x")])
        try require(replaced.dropped == history.count && replaced.start == 0 && replaced.messages.count == 1, "An unrelated transcript is replaced")
        print("PASS incremental chat transport and full-screen redraw fallback")

        let diff = GitDiff(path: "test.swift", sections: [GitDiffSection(kind: .unstaged, patch: "@@ -1 +1 @@\n-old\n+new\n")])
        let reply = try RemoteReply.success(RemoteDiff(diff))
        let restored = try reply.decode(RemoteDiff.self).diff
        try require(restored.sections.first?.patch == diff.sections.first?.patch, "Diff patches survive transport")
        try require(restored.sections.first?.additions == 1, "Derived diff rows are reconstructed locally")
        print("PASS remote diff round trip")

        for hosting in [GitHosting.github, .gitlab] {
            let snapshot = RemoteSnapshot(hosting: hosting,
                repository: RemoteRepository(nameWithOwner: "team/project", url: "https://example.invalid/team/project", description: nil),
                changeRequest: ChangeRequest(number: 7, title: "Review", url: "https://example.invalid/7", state: "OPEN", isDraft: false,
                    headRefName: "feature", headRefOid: "abc", baseRefName: "main", reviewDecision: nil,
                    statusCheckRollup: [RemoteCheck(name: "Tests", context: nil, status: "completed", conclusion: "SUCCESS", state: nil, detailsUrl: nil, targetUrl: nil)]),
                runs: [PipelineRun(databaseId: 3, displayTitle: "Build", workflowName: "CI", status: "completed", conclusion: "SUCCESS", headSha: "abc", url: "https://example.invalid/3")],
                changeRequestError: nil, checksError: nil)
            let transported = try RemoteReply.success(snapshot).decode(RemoteSnapshot.self)
            try require(transported == snapshot, "GitHub and GitLab reviews/checks survive mobile transport")
        }
        print("PASS GitHub and GitLab inspector round trip")

        let rejection = try JSONEncoder().encode(RemoteRejection("Versions incompatibles."))
        guard case .failure(let message) = try JSONDecoder().decode(RemoteEvent.self, from: rejection) else {
            throw RemoteError(message: "FAIL: A rejection must decode as a stream failure")
        }
        try require(message == "Versions incompatibles.", "A rejection carries its message to a stream")
        let rejectedReply = try JSONDecoder().decode(RemoteReply.self, from: rejection)
        try require(rejectedReply.error == "Versions incompatibles.", "A rejection carries its message to a request")
        let entries = (0..<60_000).map { "/Users/someone/Developer/project/Sources/Generated/File\($0).swift" }
        let fitted = try RemoteReply.fitting(entries) { kept, omitted in [String(omitted)] + kept }
        try require((fitted.payload?.count ?? .max) <= RemoteProtocol.maximumPayload, "A long list is trimmed to fit one frame")
        let kept = try fitted.decode([String].self)
        try require(kept.count > 10_000, "A trimmed list keeps as many entries as fit")
        try require(Int(kept[0]).map { $0 + kept.count - 1 } == entries.count, "A trimmed list reports how many entries were left out")
        print("PASS version rejections and oversized lists fit the mobile protocol")
    }
}
