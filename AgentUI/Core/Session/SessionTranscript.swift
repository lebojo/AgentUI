import Foundation
import Observation

@MainActor @Observable final class SessionTranscript {
    private(set) var source: SessionChatSource = .terminal
    private(set) var messages: [SessionMessage] = []
    @ObservationIgnored private var anchor = ""
    @ObservationIgnored private var latest = ""

    func sent(_ text: String) {
        guard source == .terminal else { return }
        anchor = String(latest.suffix(2_048))
        messages.append(SessionMessage(kind: .input, text: text))
        messages.append(SessionMessage(kind: .output, text: ""))
        messages.trimHistory(keepingAtLeast: 2)
    }

    func update(screen: String) {
        guard source == .terminal else { return }
        let text = String(decoding: screen.utf8.suffix(65_536), as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .newlines)
        guard latest != text else { return }
        latest = text
        let output: String
        if !anchor.isEmpty, let range = text.utf8.firstRange(of: anchor.utf8) {
            output = String(text[range.upperBound...]).trimmingCharacters(in: .newlines)
        } else {
            output = text
        }
        if messages.last?.kind == .output {
            messages[messages.count - 1].text = output
        } else {
            messages.append(SessionMessage(kind: .output, text: output))
        }
        messages.trimHistory(keepingAtLeast: 2)
    }

    func useJournal(_ messages: [SessionMessage], from source: SessionChatSource) {
        if self.source != source { self.source = source }
        if self.messages != messages { self.messages = messages }
    }

    func useTerminal() {
        guard source != .terminal else { return }
        source = .terminal
        messages = []
        anchor = ""
        latest = ""
    }
}
