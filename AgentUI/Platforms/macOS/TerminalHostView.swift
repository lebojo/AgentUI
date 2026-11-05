import AppKit

final class TerminalHostView: NSView {
    private static let insets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 8)

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
        let insets = Self.insets
        let available = NSRect(x: insets.left, y: insets.top,
                               width: max(0, bounds.width - insets.left - insets.right),
                               height: max(0, bounds.height - insets.top - insets.bottom))
        let frame = backingAlignedRect(available, options: .alignAllEdgesNearest)
        terminal.setFrameOrigin(frame.origin)
        terminal.setFrameSize(frame.size)
    }
}
