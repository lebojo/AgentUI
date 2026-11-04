import SwiftUI
import SwiftTerm
import Observation

@MainActor @Observable final class MobileTerminalSession: NSObject, @preconcurrency TerminalViewDelegate {
    let identity: UUID
    let isChat: Bool
    private(set) var messages: [SessionMessage] = []
    private(set) var chatSource: SessionChatSource = .terminal
    private(set) var hasExited = false
    private(set) var exitCode: Int32?
    private(set) var canvasSize = CGSize.zero
    @ObservationIgnored let view: TerminalView?
    @ObservationIgnored private var applyingOutput = false
    @ObservationIgnored private var viewport = CGSize.zero
    @ObservationIgnored private var requestedGrid: TerminalGridSize?
    @ObservationIgnored private var hostGridChanges = 0
    @ObservationIgnored private var reclaimedHostGridChange: Int?
    @ObservationIgnored private var gridRequest: Task<Void, Never>?
    @ObservationIgnored private let sendInput: (Data) -> Void
    @ObservationIgnored private let requestGrid: (TerminalGridSize) -> Void

    init(identity: UUID, isChat: Bool, sendInput: @escaping (Data) -> Void, requestGrid: @escaping (TerminalGridSize) -> Void) {
        self.identity = identity
        self.isChat = isChat
        self.sendInput = sendInput
        self.requestGrid = requestGrid
        view = isChat ? nil : TerminalView(frame: .zero)
        super.init()
        view?.font = .monospacedSystemFont(ofSize: TerminalAppearance.defaultFontSize, weight: .regular)
        view?.terminalDelegate = self
    }

    private var hostUsesRequestedGrid: Bool {
        guard let view, let requestedGrid else { return false }
        let terminal = view.getTerminal()
        return terminal.cols == requestedGrid.columns && terminal.rows == requestedGrid.rows
    }

    private var fittingGrid: TerminalGridSize? {
        guard let view, viewport.width > 0, viewport.height > 0 else { return nil }
        let terminal = view.getTerminal()
        let size = view.getOptimalFrameSize().size
        guard size.width > 0, size.height > 0 else { return nil }
        return TerminalGridSize(columns: Int(viewport.width * CGFloat(terminal.cols) / size.width),
                                rows: Int(viewport.height * CGFloat(terminal.rows) / size.height))
    }

    @discardableResult func apply(_ snapshot: RemoteTerminalSnapshot) -> Bool {
        if hasExited != snapshot.hasExited { hasExited = snapshot.hasExited }
        if exitCode != snapshot.exitCode { exitCode = snapshot.exitCode }
        if chatSource != snapshot.chatSource { chatSource = snapshot.chatSource }
        guard (0...messages.count).contains(snapshot.transcriptDropped),
              (0...(messages.count - snapshot.transcriptDropped)).contains(snapshot.transcriptStart) else { return false }
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
            hostGridChanges += 1
        }
        if hostUsesRequestedGrid { reclaimedHostGridChange = nil }
        updateCanvasSize()
        if !snapshot.output.isEmpty { view.feed(byteArray: Array(snapshot.output)[...]) }
        return true
    }

    func fit(_ viewport: CGSize) {
        guard self.viewport != viewport else { return }
        self.viewport = viewport
        scheduleGridRequest()
    }

    func setFontSize(_ size: Double) {
        guard let view, view.font.pointSize != CGFloat(size) else { return }
        let origin = view.frame.origin
        view.frame = .zero
        view.font = .monospacedSystemFont(ofSize: size, weight: .regular)
        updateCanvasSize()
        view.frame = CGRect(origin: origin, size: canvasSize)
        scheduleGridRequest()
    }

    func reclaimGrid() {
        guard let requestedGrid else { return }
        reclaimedHostGridChange = hostGridChanges
        requestGrid(requestedGrid)
    }

    private func updateCanvasSize() {
        guard let view else { return }
        let size = view.getOptimalFrameSize().size
        let canvas = CGSize(width: ceil(size.width), height: ceil(size.height))
        if canvasSize != canvas { canvasSize = canvas }
    }

    private func scheduleGridRequest() {
        gridRequest?.cancel()
        gridRequest = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            self?.requestFittingGrid()
        }
    }

    private func requestFittingGrid() {
        guard let grid = fittingGrid, grid != requestedGrid else { return }
        requestedGrid = grid
        requestGrid(grid)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !applyingOutput else { return }
        if !hostUsesRequestedGrid, reclaimedHostGridChange != hostGridChanges { reclaimGrid() }
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
