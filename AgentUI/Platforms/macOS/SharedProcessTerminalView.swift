import SwiftTerm
import Foundation

class SharedProcessTerminalView: LocalProcessTerminalView {
    var received: ((Data) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        received?(Data(slice))
    }
}
