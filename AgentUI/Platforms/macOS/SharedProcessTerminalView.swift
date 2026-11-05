import SwiftTerm
import Foundation

@MainActor protocol TerminalOutputReceiver: AnyObject {
    func terminalReceived(_ slice: ArraySlice<UInt8>)
}

class SharedProcessTerminalView: LocalProcessTerminalView {
    weak var outputReceiver: TerminalOutputReceiver?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        outputReceiver?.terminalReceived(slice)
    }
}
