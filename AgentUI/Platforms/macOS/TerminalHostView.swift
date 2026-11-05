import AppKit
import SwiftUI

final class TerminalHostView: NSView {
    let terminal: ActivityTerminalView

    override var isFlipped: Bool { true }

    init(terminal: ActivityTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        clipsToBounds = true
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = []
        addSubview(terminal)
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutTerminal()
    }

    private func layoutTerminal() {
        let insets = Dimension.Detail.terminalInsets
        let available = NSRect(x: insets.leading, y: insets.top,
                               width: max(0, bounds.width - insets.leading - insets.trailing),
                               height: max(0, bounds.height - insets.top - insets.bottom))
        let frame = backingAlignedRect(available, options: .alignAllEdgesNearest)
        terminal.setFrameOrigin(frame.origin)
        terminal.setFrameSize(frame.size)
    }
}
