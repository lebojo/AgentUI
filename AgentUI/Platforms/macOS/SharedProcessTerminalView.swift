import SwiftTerm
import Foundation

class SharedProcessTerminalView: LocalProcessTerminalView {
    var received: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        received?(slice)
    }
}
