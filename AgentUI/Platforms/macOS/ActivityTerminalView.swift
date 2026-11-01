import Foundation
import SwiftTerm

final class ActivityTerminalView: SharedProcessTerminalView {
    private(set) var lastOutput = Date.distantPast

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutput = .now
        super.dataReceived(slice: slice)
    }

    var visibleLines: [String] {
        let terminal = getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
    }
}
