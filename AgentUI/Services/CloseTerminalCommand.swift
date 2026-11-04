import AppKit

@MainActor final class CloseTerminalCommand: NSObject, NSMenuItemValidation {
    private let store: WorkspaceStore
    private let floating: FloatingTerminalStore
    private var monitor: Any?
    private var observer: NSObjectProtocol?

    init(store: WorkspaceStore, floating: FloatingTerminalStore) {
        self.store = store
        self.floating = floating
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.charactersIgnoringModifiers?.lowercased() == "w",
                  event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
                  self.canCloseFloatingTerminal || (self.canCloseTerminal && event.window == NSApp.mainWindow) else { return event }
            self.close(nil)
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.installMenuAction() }
        }
        DispatchQueue.main.async { [weak self] in self?.installMenuAction() }
    }

    private var canCloseFloatingTerminal: Bool {
        floating.isKey && floating.state.focusedID != nil && NSApp.modalWindow == nil
    }

    private var canCloseTerminal: Bool {
        !floating.isKey && !store.isReadOnly && store.selectedContext != nil &&
        NSApp.modalWindow == nil && NSApp.mainWindow?.attachedSheet == nil &&
        NSApp.keyWindow == NSApp.mainWindow
    }

    @objc func close(_ sender: Any?) {
        if canCloseFloatingTerminal { floating.closeFocused() }
        else if canCloseTerminal, store.selectedSubagent != nil { store.leaveSubagent() }
        else if canCloseTerminal, let id = store.selectedContext?.terminal.id { store.closeTerminal(id) }
        else { NSApp.keyWindow?.performClose(sender) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = if canCloseFloatingTerminal { String(localized: "Close Terminal") }
            else if !canCloseTerminal { String(localized: "Close Window") }
            else if store.selectedSubagent != nil { String(localized: "Close Subagent") }
            else { String(localized: "Close Terminal") }
        return NSApp.keyWindow != nil
    }

    private func installMenuAction() {
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == #selector(NSWindow.performClose(_:)), item.keyEquivalent == "w",
                   item.keyEquivalentModifierMask == .command {
                    item.target = self
                    item.action = #selector(close(_:))
                }
                if let submenu = item.submenu { visit(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { visit(menu) }
    }
}
