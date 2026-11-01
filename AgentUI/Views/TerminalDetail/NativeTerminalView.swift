import AppKit
import SwiftUI

struct NativeTerminalView: NSViewRepresentable {
    final class Coordinator {
        var appliedAppearance: TerminalAppearance?
        var appliedColorScheme: ColorScheme?
        var wasFocused = false
        var focus: () -> Void = {}
        var mouseMonitor: Any?
    }

    let session: TerminalSession
    let appearance: TerminalAppearance
    let isFocused: Bool
    let focus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.setAccessibilityLabel(String(localized: "Interactive Terminal"))
        let terminal = session.view
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            terminal.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            terminal.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8)
        ])
        applyAppearance(context: context)
        let coordinator = context.coordinator
        coordinator.focus = focus
        coordinator.wasFocused = isFocused
        coordinator.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak host] event in
            if let host, event.window === host.window, host.bounds.contains(host.convert(event.locationInWindow, from: nil)) {
                coordinator.focus()
            }
            return event
        }
        if isFocused { DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) } }
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        applyAppearance(context: context)
        context.coordinator.focus = focus
        if isFocused, !context.coordinator.wasFocused {
            let terminal = session.view
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
        context.coordinator.wasFocused = isFocused
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.mouseMonitor { NSEvent.removeMonitor(monitor) }
        coordinator.mouseMonitor = nil
    }

    private func applyAppearance(context: Context) {
        let colorScheme = context.environment.colorScheme
        guard context.coordinator.appliedAppearance != appearance || context.coordinator.appliedColorScheme != colorScheme else { return }
        context.coordinator.appliedAppearance = appearance
        context.coordinator.appliedColorScheme = colorScheme
        session.view.apply(appearance)
    }
}
