import AppKit

/// Keep the native Close menu and terminal keyboard handling on the same path.
@MainActor final class CloseTerminalCommand: NSObject, NSMenuItemValidation {
    private let store: WorkspaceStore
    private var monitor: Any?
    private var observer: NSObjectProtocol?

    init(store: WorkspaceStore) {
        self.store = store
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.charactersIgnoringModifiers?.lowercased() == "w",
                  event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
                  self.canCloseTerminal, event.window == NSApp.mainWindow else { return event }
            self.close(nil)
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.installMenuAction() }
        }
        DispatchQueue.main.async { [weak self] in self?.installMenuAction() }
    }

    private var canCloseTerminal: Bool {
        !store.isReadOnly && store.context(for: store.selection) != nil &&
        NSApp.modalWindow == nil && NSApp.mainWindow?.attachedSheet == nil &&
        NSApp.keyWindow == NSApp.mainWindow
    }

    @objc func close(_ sender: Any?) {
        if canCloseTerminal, let id = store.selection { store.closeTerminal(id) }
        else { NSApp.keyWindow?.performClose(sender) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = canCloseTerminal ? "Fermer le terminal" : "Fermer la fenêtre"
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
