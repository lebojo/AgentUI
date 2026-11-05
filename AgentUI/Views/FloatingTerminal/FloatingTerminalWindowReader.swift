import AppKit
import SwiftUI

struct FloatingTerminalWindowReader: NSViewRepresentable {
    final class ReaderView: NSView {
        private let store: FloatingTerminalStore

        init(store: FloatingTerminalStore) {
            self.store = store
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            store.attach(window)
        }
    }

    @Environment(FloatingTerminalStore.self) private var floating

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(store: floating)
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {}
}
