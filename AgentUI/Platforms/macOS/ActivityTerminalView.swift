import AppKit
import SwiftTerm

final class ActivityTerminalView: SharedProcessTerminalView {
    private(set) var lastOutput = Date.distantPast
    var pasted: () -> Void = {}
    var remoteGrid: TerminalGridSize? {
        didSet {
            guard remoteGrid != oldValue else { return }
            if remoteGrid == nil {
                ptyGrid = nil
                setFrameSize(frame.size)
            } else {
                fitRemoteGrid()
            }
        }
    }
    private var ptyGrid: TerminalGridSize?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutput = .now
        super.dataReceived(slice: slice)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitRemoteGrid()
    }

    override func paste(_ sender: Any) {
        pasted()
        super.paste(sender)
    }

    override func getWindowSize() -> winsize {
        let size = super.getWindowSize()
        guard let remoteGrid, size.ws_col > 0, size.ws_row > 0 else { return size }
        return winsize(ws_row: UInt16(remoteGrid.rows), ws_col: UInt16(remoteGrid.columns),
                       ws_xpixel: UInt16(clamping: Int(size.ws_xpixel) / Int(size.ws_col) * remoteGrid.columns),
                       ws_ypixel: UInt16(clamping: Int(size.ws_ypixel) / Int(size.ws_row) * remoteGrid.rows))
    }

    func fitRemoteGrid() {
        let terminal = getTerminal()
        guard let remoteGrid, terminal.cols != remoteGrid.columns || terminal.rows != remoteGrid.rows else { return }
        let restoresPtyGrid = ptyGrid == remoteGrid
        selectNone()
        terminal.resize(cols: remoteGrid.columns, rows: remoteGrid.rows)
        sizeChanged(source: terminal)
        ptyGrid = remoteGrid
        if restoresPtyGrid { askForegroundProcessToRedraw() }
        invalidateSearchAndAccessibility()
    }

    var visibleLines: [String] {
        let terminal = getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }

    private func askForegroundProcessToRedraw() {
        guard process.running else { return }
        let group = tcgetpgrp(process.childfd)
        if group > 0 { kill(-group, SIGWINCH) }
    }

    private func invalidateSearchAndAccessibility() {
        feed(byteArray: [])
    }
}
