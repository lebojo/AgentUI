#if DEBUG
import AppKit
import SwiftTerm

/// Test-only operations, enabled only for an explicitly isolated workspace.
@MainActor enum DevelopmentCapture {
    static func execute(_ request: BridgeRequest, store: WorkspaceStore) async throws -> BridgeResponse {
        switch request.action {
        case "debug.capture":
            guard let path = request.path,
                  let window = NSApp.windows.first(where: { $0.contentView != nil && $0.title != "" }),
                  let view = window.contentView else { throw WorkspaceError(message: "No window to capture") }
            if let width = request.command.first.flatMap(Double.init) {
                window.setContentSize(NSSize(width: width, height: width < 900 ? 520 : 740))
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.appearance = NSAppearance(named: request.name == "light" ? .aqua : .darkAqua)
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw WorkspaceError(message: "No bitmap") }
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw WorkspaceError(message: "No PNG") }
            try data.write(to: URL(fileURLWithPath: path))
            return BridgeResponse(ok: true, message: String(window.windowNumber), path: path)
        case "debug.activate":
            if let window = NSApp.windows.first(where: { $0.contentView != nil && $0.canBecomeMain && !($0 is NSPanel) }) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeMain()
                return BridgeResponse(ok: true, message: NSApp.keyWindow == window ? "key" : "waiting")
            }
            throw WorkspaceError(message: "No workspace window to activate")
        case "debug.closeShortcut":
            guard let window = NSApp.keyWindow,
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13) else {
                throw WorkspaceError(message: "No key window")
            }
            if request.name == "menu" { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
            else { NSApp.sendEvent(event) }
            return BridgeResponse(ok: true, message: window.isVisible ? "visible" : "closed")
        case "debug.wake":
            if let id = request.projectID { store.wakeProject(id) }
        case "debug.import":
            if let path = request.path { await store.importFolder(URL(fileURLWithPath: path)) }
        case "debug.addLocation":
            if let path = request.path { try await store.addLocation(URL(fileURLWithPath: path)) }
        case "debug.git":
            guard let id = request.name.flatMap(UUID.init(uuidString:)), let context = store.context(for: id) else {
                throw WorkspaceError(message: "Unknown test terminal")
            }
            return BridgeResponse(ok: true, message: store.sessions.branch(for: id, initialPath: context.worktree.path)?.name,
                                  path: store.sessions.session(id)?.currentDirectory)
        case "debug.send":
            guard let id = request.name.flatMap(UUID.init(uuidString:)), let session = store.sessions.session(id) else {
                throw WorkspaceError(message: "Test terminal is not running")
            }
            let bytes = Array((request.command.joined(separator: "\n") + "\n").utf8)
            session.view.process.send(data: bytes[...])
        case "debug.flush":
            try await store.flushPersistence()
        case "debug.cancelWorktree":
            guard let projectID = request.projectID, let branch = request.branch, let marker = request.path else {
                throw WorkspaceError(message: "Missing cancellation fixture")
            }
            let creation = Task { try await store.createWorktree(projectID: projectID, branch: branch) }
            for _ in 0..<200 {
                if FileManager.default.fileExists(atPath: marker) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            creation.cancel()
            do {
                _ = try await creation.value
                throw WorkspaceError(message: "Cancellation unexpectedly succeeded")
            } catch let error as WorktreeCreationError {
                try await store.flushPersistence()
                return BridgeResponse(ok: true, message: error.localizedDescription, path: error.path, workspace: store.state)
            }
        case "debug.refresh":
            if let id = request.projectID { await store.refreshWorktrees(id) }
        case "debug.select":
            store.selection = request.name.flatMap(UUID.init(uuidString:))
        case "debug.folder":
            let folder = store.addFolder(request.name ?? "Studio")
            if let project = request.projectID { store.moveProject(project, to: folder) }
        case "debug.stop":
            store.sessions.stopAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        default: throw WorkspaceError(message: "Unknown debug operation")
        }
        return BridgeResponse(ok: true)
    }
}
#endif
