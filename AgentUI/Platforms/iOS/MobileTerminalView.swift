import SwiftUI
import SwiftTerm
import Observation

@MainActor @Observable final class MobileTerminalSession: NSObject, @preconcurrency TerminalViewDelegate {
    let identity: UUID
    let isChat: Bool
    private(set) var messages: [SessionMessage] = []
    private(set) var chatSource: SessionChatSource = .terminal
    private(set) var hasExited = false
    private(set) var canvasSize = CGSize.zero
    @ObservationIgnored let view: TerminalView?
    @ObservationIgnored private var applyingOutput = false
    @ObservationIgnored private let sendInput: (Data) -> Void

    init(identity: UUID, isChat: Bool, sendInput: @escaping (Data) -> Void) {
        self.identity = identity
        self.isChat = isChat
        self.sendInput = sendInput
        view = isChat ? nil : TerminalView(frame: .zero)
        super.init()
        view?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view?.terminalDelegate = self
    }

    @discardableResult func apply(_ snapshot: RemoteTerminalSnapshot) -> Bool {
        if hasExited != snapshot.hasExited { hasExited = snapshot.hasExited }
        if chatSource != snapshot.chatSource { chatSource = snapshot.chatSource }
        guard snapshot.transcriptDropped <= messages.count,
              snapshot.transcriptStart <= messages.count - snapshot.transcriptDropped else { return false }
        let changesTranscript = snapshot.transcriptDropped > 0 || snapshot.transcriptStart < messages.count - snapshot.transcriptDropped
            || !snapshot.transcript.isEmpty || snapshot.transcriptAppend != nil
        if changesTranscript {
            var updated = messages
            updated.removeFirst(snapshot.transcriptDropped)
            updated.replaceSubrange(snapshot.transcriptStart..., with: snapshot.transcript)
            if let append = snapshot.transcriptAppend {
                guard let last = updated.last, last.id == append.id, let text = append.applied(to: last.text) else { return false }
                updated[updated.count - 1].text = text
            }
            messages = updated
        }
        guard let view else { return true }
        applyingOutput = true
        defer { applyingOutput = false }
        let terminal = view.getTerminal()
        if terminal.cols != snapshot.columns || terminal.rows != snapshot.rows {
            terminal.resize(cols: snapshot.columns, rows: snapshot.rows)
        }
        let size = view.getOptimalFrameSize().size
        let canvas = CGSize(width: ceil(size.width), height: ceil(size.height))
        if canvasSize != canvas { canvasSize = canvas }
        if !snapshot.output.isEmpty { view.feed(byteArray: Array(snapshot.output)[...]) }
        return true
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !applyingOutput else { return }
        sendInput(Data(data))
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme) else { return }
        UIApplication.shared.open(url)
    }
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
