import SwiftUI

struct SessionExitLabel: View {
    let code: Int32?

    private var title: String {
        switch code {
        case nil: String(localized: "Session ended")
        case 127: String(localized: "Command not found (127): check that it’s installed and in your shell’s PATH")
        case let code?: String(localized: "Session ended (\(code))")
        }
    }

    var body: some View {
        Label(title, systemImage: "stop.circle")
    }
}
