import AppKit
import SwiftTerm

final class ActivityTerminalView: SharedProcessTerminalView {
    private(set) var lastOutput = Date.distantPast
    var usedLocally: () -> Void = {}
    var remoteGrid: TerminalGridSize? {
        didSet {
            guard remoteGrid != oldValue else { return }
            setFrameSize(oldValue == nil ? frame.size : hostedSize)
        }
    }
    private var hostedSize = NSSize.zero
    private var answersHost = false
    private var forwardsRemoteInput = false

    var visibleLines: [String] {
        let terminal = getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutput = .now
        answersHost = true
        defer { answersHost = false }
        super.dataReceived(slice: slice)
    }

    override func setFrameSize(_ newSize: NSSize) {
        hostedSize = newSize
        guard let pinned = remoteGrid.flatMap(frameSize(for:)) else { return super.setFrameSize(newSize) }
        if pinned != frame.size { super.setFrameSize(pinned) }
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard remoteGrid != nil, !answersHost, !forwardsRemoteInput, !data.isTerminalFocusReport else { return }
        usedLocally()
    }

    func sendRemoteInput(_ data: ArraySlice<UInt8>) {
        forwardsRemoteInput = true
        defer { forwardsRemoteInput = false }
        send(source: self, data: data)
    }

    func refitRemoteGrid() {
        guard remoteGrid != nil else { return }
        setFrameSize(hostedSize)
    }

    private func frameSize(for grid: TerminalGridSize) -> NSSize? {
        let terminal = getTerminal()
        return grid.frameSize(scaling: getOptimalFrameSize().size, columns: terminal.cols, rows: terminal.rows,
                              scrollerWidth: NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollerStyle))
    }
}
