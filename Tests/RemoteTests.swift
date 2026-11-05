import CoreImage
import Foundation

@main struct RemoteTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw RemoteError(message: "FAIL: " + message) }
    }

    @MainActor static func main() throws {
        for address in ["192.168.1.42", "10.0.0.1", "172.16.0.1", "172.31.255.254", "127.0.0.1", "::1", "fd00::1", " 192.168.0.1\n", "::ffff:192.168.1.42"] {
            _ = try RemoteProtocol.host(address)
        }
        for address in ["", "8.8.8.8", "172.32.0.1", "192.169.1.1", "https://192.168.1.1", "mac.local", "192.168.1.1:80", "2001:4860:4860::8888", "::ffff:8.8.8.8"] {
            do {
                _ = try RemoteProtocol.host(address)
                throw RemoteError(message: "FAIL: accepted " + address)
            } catch let error as RemoteError {
                try require(!error.message.hasPrefix("FAIL:"), error.message)
            }
        }
        print("PASS literal LAN address validation")

        let invitation = PairingInvitation(hostID: UUID(), name: "Jordan’s MacBook Pro & Co", addresses: ["192.168.1.42", "10.0.0.5"],
                                           code: RemotePairing.newCode())
        let scanned = try PairingInvitation(scanned: invitation.link)
        try require(scanned == invitation, "QR link round-trips every field")
        let padded = try PairingInvitation(scanned: " \(invitation.link)\n")
        try require(padded.addresses == invitation.addresses, "QR link tolerates surrounding whitespace")
        let mixed = try PairingInvitation(scanned: invitation.link.replacingOccurrences(of: "10.0.0.5", with: "8.8.8.8"))
        try require(mixed.addresses == ["192.168.1.42"], "QR link drops public addresses")
        let rejected = ["https://example.com", "agentui://other?id=\(invitation.hostID)",
                        invitation.link.replacingOccurrences(of: invitation.code, with: "NOPE"),
                        invitation.link.replacingOccurrences(of: "192.168.1.42,10.0.0.5", with: "8.8.8.8"),
                        invitation.link.replacingOccurrences(of: invitation.hostID.uuidString, with: "mac")]
        for text in rejected {
            do {
                _ = try PairingInvitation(scanned: text)
                throw RemoteError(message: "FAIL: accepted QR " + text)
            } catch let error as RemoteError {
                try require(!error.message.hasPrefix("FAIL:"), error.message)
            }
        }
        let image = try QRCode.image(encoding: invitation.link).map(CIImage.init(cgImage:)) ?? { throw RemoteError(message: "FAIL: QR image") }()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let decoded = detector?.features(in: image.transformed(by: CGAffineTransform(scaleX: 8, y: 8))).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        try require(decoded == [invitation.link], "Generated QR code decodes back to the pairing link")
        let saved = SavedHost(name: "Mac", addresses: ["192.168.1.42", "10.0.0.5"])
        try require(saved.preferring("10.0.0.5").addresses == ["10.0.0.5", "192.168.1.42"], "Saved host moves the working address first")
        try require(saved.pairingAccount.hasSuffix(saved.id.uuidString), "Each saved host keeps its own keychain account")
        let persisted = try JSONDecoder().decode(SavedHost.self, from: JSONEncoder().encode(saved))
        try require(persisted == saved, "Saved host persists")
        let interfaces = [LocalAddress(interface: "bridge100", value: "192.168.64.1"), LocalAddress(interface: "utun4", value: "10.8.0.2"),
                          LocalAddress(interface: "en10", value: "10.0.0.9"), LocalAddress(interface: "en1", value: "192.168.1.60"),
                          LocalAddress(interface: "en0", value: "192.168.1.42"), LocalAddress(interface: "en0", value: "169.254.3.4")]
        try require(LocalAddress.reachable(interfaces) == ["192.168.1.42", "192.168.1.60", "10.0.0.9"], "Mac lists Wi-Fi and Ethernet first, without VM, VPN or link-local addresses")
        let fallback = [LocalAddress(interface: "bridge0", value: "192.168.2.1"), LocalAddress(interface: "en0", value: "169.254.3.4")]
        try require(LocalAddress.reachable(fallback) == ["192.168.2.1"], "Mac falls back to other interfaces when Ethernet and Wi-Fi have no address")
        try require(LocalAddress.reachable([LocalAddress(interface: "en0", value: "169.254.3.4")]) == ["169.254.3.4"], "Mac keeps link-local as a last resort")
        print("PASS QR pairing link and saved hosts")

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
        let rows = (0..<300).map { "row \($0)" }.joined(separator: "\n")
        let run = "$ cat rows\n" + rows + "\n"
        let repeated = SessionTranscript()
        repeated.update(screen: run + run + "$ ")
        repeated.sent("cat rows")
        repeated.update(screen: run + run + run + "$ ")
        try require(repeated.messages.last?.text == "cat rows\n" + rows + "\n$ ", "A repeated command only shows its own output")
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
        var composed = old
        composed.text += "café"
        var decomposed = old
        decomposed.text += "cafe\u{301} ok"
        let normalization = SessionTranscriptDelta(previous: [composed], current: [decomposed])
        try require(normalization.append?.applied(to: composed.text).map { Array($0.utf8) } == Array(decomposed.text.utf8),
                    "Canonically equivalent text is rebuilt byte for byte on the phone")
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
        let terminal = UUID()
        let legacy = Data(#"{"diff":{"terminal":"\#(terminal.uuidString)","change":{"path":"a","indexStatus":"M","worktreeStatus":"M"}}}"#.utf8)
        let scoped = try JSONEncoder().encode(RemoteRequest.diff(terminal: terminal, change: GitChange(path: "a", originalPath: nil, indexStatus: "M", worktreeStatus: "M"),
                                                                 including: [.staged]))
        guard case .diff(terminal, let legacyChange, nil) = try JSONDecoder().decode(RemoteRequest.self, from: legacy),
              case .diff(terminal, legacyChange, [.staged]) = try JSONDecoder().decode(RemoteRequest.self, from: scoped) else {
            throw RemoteError(message: "FAIL: diff requests lost their scope or legacy compatibility")
        }
        print("PASS remote diff round trip and scoped diff requests")

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
        let tracked = LocalGitSnapshot(root: "/r", branch: GitBranch(name: "feature"), headSHA: "abc", changes: [],
                                       tracking: GitTracking(upstream: "origin/feature", ahead: 2, tracksSameBranch: true))
        let legacyTracking = Data(#"{"root":"/r","headSHA":"abc","changes":[],"omittedChanges":0,"tracking":{"upstream":"origin/feature","ahead":2}}"#.utf8)
        let legacySnapshot = try JSONDecoder().decode(LocalGitSnapshot.self, from: legacyTracking)
        let transportedTracking = try RemoteReply.success(tracked).decode(LocalGitSnapshot.self)
        try require(transportedTracking == tracked && legacySnapshot.tracking == GitTracking(upstream: "origin/feature", ahead: 2) && legacySnapshot.tracking?.isPublished == false,
                    "Branch tracking survives mobile transport and older payloads without the same-branch flag still decode")
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

        try testRemoteGridRequests()
        print("PASS a phone grid applies until the Mac takes it back, and only typing on the phone claims it again")
        try testPinnedFrameSize()
        print("PASS the pinned terminal frame makes SwiftTerm compute exactly the phone grid")
    }

    static func testRemoteGridRequests() throws {
        let phone = UUID()
        let tablet = UUID()
        let portrait = TerminalGridSize(columns: 45, rows: 50)
        let landscape = TerminalGridSize(columns: 100, rows: 20)
        let tabletGrid = TerminalGridSize(columns: 120, rows: 40)
        try require([UInt8]("\u{1b}[I".utf8).isTerminalFocusReport && Data("\u{1b}[O".utf8).isTerminalFocusReport,
                    "Focus-in and focus-out reports are recognised")
        try require(![UInt8]("\u{1b}[Ix".utf8).isTerminalFocusReport && !Data("I".utf8).isTerminalFocusReport && !Data().isTerminalFocusReport,
                    "Typed text is never a focus report")
        var grids = RemoteGridRequests()
        grids.takeBack()
        try require(grids.isEmpty && grids.size == nil, "Using an unwatched terminal on the Mac leaves no state behind")
        grids.request(portrait, by: phone)
        try require(grids.size == portrait, "A phone grid applies as soon as the phone asks")
        grids.request(tabletGrid, by: tablet)
        try require(grids.size == tabletGrid, "The latest viewer grid applies")
        grids.receive(Data("x".utf8), from: phone)
        try require(grids.size == portrait, "Typing on a phone gives the terminal its grid")
        grids.takeBack()
        try require(grids.size == nil && !grids.isEmpty, "Using the terminal on the Mac returns it to the Mac grid")
        grids.request(landscape, by: phone)
        try require(grids.size == nil, "Rotating the phone or changing its text size never takes the terminal back from the Mac")
        grids.receive(Data("\u{1b}[O".utf8), from: phone)
        grids.receive(Data("\u{1b}[I".utf8), from: phone)
        try require(grids.size == nil, "Focus reports sent when the phone keyboard opens or closes are not typing")
        grids.withdraw(phone)
        grids.request(landscape, by: phone)
        try require(grids.size == nil, "A phone reconnecting after a network blip doesn't take the terminal back")
        grids.receive(Data("y".utf8), from: UUID())
        try require(grids.size == nil, "Typing from a viewer without a grid, such as Chat, claims nothing")
        grids.receive(Data("y".utf8), from: phone)
        try require(grids.size == landscape, "Typing on the phone claims its latest grid again")
        grids.withdraw(phone)
        try require(grids.size == tabletGrid, "When a phone leaves the terminal or switches to Chat, the next viewer grid applies")
        grids.withdraw(tablet)
        try require(grids.isEmpty && grids.size == nil, "The Mac grid returns once no viewer shows the terminal")
        grids.request(portrait, by: phone)
        grids.takeBack()
        grids.withdraw(phone)
        try require(grids.isEmpty && grids.size == nil, "The last viewer leaving a terminal the Mac took back leaves no state behind")
        grids.request(tabletGrid, by: tablet)
        try require(grids.size == tabletGrid, "A viewer opening the terminal afterwards gets its grid without typing")
    }

    static func testPinnedFrameSize() throws {
        let grids = [TerminalGridSize(columns: 20, rows: 5), TerminalGridSize(columns: 45, rows: 50),
                     TerminalGridSize(columns: 80, rows: 24), TerminalGridSize(columns: 211, rows: 63), TerminalGridSize(columns: 400, rows: 200)]
        for cell in [CGSize(width: 7, height: 14), CGSize(width: 7.2246, height: 16.5), CGSize(width: 7.8, height: 17),
                     CGSize(width: 8.4375, height: 19.2), CGSize(width: 15.6, height: 31.0001)] {
            for scroller: CGFloat in [0, 15, 16] {
                for current in [(columns: 1, rows: 1), (columns: 87, rows: 31), (columns: 400, rows: 200)] {
                    let optimal = CGSize(width: cell.width * CGFloat(current.columns) + scroller, height: cell.height * CGFloat(current.rows))
                    for grid in grids {
                        guard let size = grid.frameSize(scaling: optimal, columns: current.columns, rows: current.rows, scrollerWidth: scroller) else {
                            throw RemoteError(message: "FAIL: No frame for \(grid) with cell \(cell)")
                        }
                        try require(Int((size.width - scroller) / cell.width) == grid.columns && Int(size.height / cell.height) == grid.rows,
                                    "SwiftTerm fits \(grid.columns)x\(grid.rows) in the pinned frame \(size) for cell \(cell)")
                        try require(size.width == size.width.rounded() && size.height == size.height.rounded(), "The pinned frame is point aligned")
                    }
                }
            }
        }
        try require(TerminalGridSize(columns: 80, rows: 24).frameSize(scaling: .zero, columns: 0, rows: 0, scrollerWidth: 15) == nil,
                    "An empty terminal has no pinned frame")
    }
}
