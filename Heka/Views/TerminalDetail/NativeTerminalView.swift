import AppKit
import SwiftUI

struct NativeTerminalView: NSViewRepresentable {
    final class Coordinator {
        var appliedAppearance: TerminalAppearance?
        var appliedColorScheme: ColorScheme?
        var wasFocused = false
        var focus: () -> Void = {}
        var eventMonitor: Any?
    }

    let session: TerminalSession
    let appearance: TerminalAppearance
    let isFocused: Bool
    let focus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let terminal = session.view
        let host = TerminalHostView(terminal: terminal)
        host.setAccessibilityLabel(String(localized: "Interactive Terminal"))
        applyAppearance(context: context)
        let coordinator = context.coordinator
        coordinator.focus = focus
        coordinator.wasFocused = isFocused
        coordinator.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .keyUp]) { [weak host] event in
            guard let host, event.window === host.window else { return event }
            if event.type == .keyDown || event.type == .keyUp {
                guard host.window?.firstResponder === host.terminal else { return event }
                return host.terminal.routeKey(event)
            } else if host.bounds.contains(host.convert(event.locationInWindow, from: nil)) {
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
        if let monitor = coordinator.eventMonitor { NSEvent.removeMonitor(monitor) }
        coordinator.eventMonitor = nil
    }

    private func applyAppearance(context: Context) {
        let colorScheme = context.environment.colorScheme
        guard context.coordinator.appliedAppearance != appearance || context.coordinator.appliedColorScheme != colorScheme else { return }
        context.coordinator.appliedAppearance = appearance
        context.coordinator.appliedColorScheme = colorScheme
        session.view.apply(appearance)
        session.view.refitRemoteGrid()
    }
}
