import AppKit
import SwiftUI

struct FloatingTerminalWindowReader: NSViewRepresentable {
    final class ReaderView: NSView {
        var store: FloatingTerminalStore?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            store?.attach(window)
        }
    }

    @Environment(FloatingTerminalStore.self) private var floating

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.store = floating
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.store = floating
        floating.attach(nsView.window)
    }
}
