import SwiftUI
import SwiftTerm

private struct Viewport: View {
    let session: MobileTerminalSession

    var body: some View {
        MobileTerminalViewport(session: session)
    }
}

@main @MainActor final class MobileTerminalTests: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = MirrorTestScene.self
        return configuration
    }
}

@MainActor private final class MirrorTestScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        Task {
            var result = ""
            do { result = try await run() }
            catch { result = "FAIL: \(error)" }
            let url = URL.documentsDirectory.appendingPathComponent("result.txt")
            try? result.write(to: url, atomically: true, encoding: .utf8)
            print(result)
        }
    }

    private func run() async throws -> String {
        var sent: [Data] = []
        var requested: [TerminalGridSize] = []
        UserDefaults.standard.removeObject(forKey: TerminalAppearance.mobileFontSizeKey)
        let session = MobileTerminalSession(identity: UUID(), isChat: false) { sent.append($0) } requestGrid: { requested.append($0) }
        let view = session.view!
        let terminal = view.getTerminal()
        func apply(_ text: String, columns: Int = 90, rows: Int = 35) {
            session.apply(RemoteTerminalSnapshot(identity: session.identity, isChat: false, output: Data(text.utf8),
                                                columns: columns, rows: rows, transcript: [], transcriptDropped: 0, transcriptStart: 0, transcriptAppend: nil,
                                                hasExited: false, exitCode: nil))
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: message, code: 1) }
        }
        apply("\u{1b}[?1h\u{1b}[3;20r\u{1b}[31mfirst")
        let attribute = terminal.currentAttribute
        apply("second\u{1b}[6n\u{1b}[c\u{1b}[?1004h")
        try require(terminal.applicationCursor && terminal.buffer.scrollTop == 2 && terminal.buffer.scrollBottom == 19 && terminal.currentAttribute == attribute,
                    "Applying another packet must preserve modes, margins and attributes")
        try await Task.sleep(for: .milliseconds(100))
        try require(sent.isEmpty, "Mirrored device queries must never reach the PTY")
        view.insertText("x")
        try await Task.sleep(for: .milliseconds(100))
        try require(sent == [Data("x".utf8)], "Real keyboard input must still reach the PTY")
        try require(requested.isEmpty, "No grid is requested before the terminal has a viewport")

        let controller = UIHostingController(rootView: Viewport(session: session))
        let window = self.window!
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(300))
        try require(view.window != nil, "Test terminal must actually attach to UIKit")
        for size in [CGSize(width: 402, height: 700), CGSize(width: 874, height: 350), CGSize(width: 402, height: 220)] {
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            view.setNeedsLayout()
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            try require(terminal.cols == 90 && terminal.rows == 35, "Attachment, rotation and keyboard viewport sizes must not change host grid")
            try require(terminal.applicationCursor && terminal.currentAttribute == attribute, "UIKit layout must preserve terminal state")
        }
        try await Task.sleep(for: .milliseconds(300))
        func fittingGrid() -> TerminalGridSize {
            let cell = view.getOptimalFrameSize().size
            let bounds = ancestorViewport()?.bounds.size ?? .zero
            return TerminalGridSize(columns: Int(bounds.width * CGFloat(terminal.cols) / cell.width),
                                    rows: Int(bounds.height * CGFloat(terminal.rows) / cell.height))
        }
        func ancestorViewport() -> MobileTerminalScrollView? {
            var ancestor = view.superview
            while ancestor != nil && !(ancestor is MobileTerminalScrollView) { ancestor = ancestor?.superview }
            return ancestor as? MobileTerminalScrollView
        }
        let fitted = requested.count
        try require(fitted > 0 && fitted <= 2 && requested.last == fittingGrid(),
                    "Viewport changes are debounced into a request for the grid that fits the phone: \(requested)")
        UserDefaults.standard.set(20.0, forKey: TerminalAppearance.mobileFontSizeKey)
        try await Task.sleep(for: .milliseconds(300))
        try require(terminal.cols == 90 && terminal.rows == 35 && terminal.applicationCursor && terminal.currentAttribute == attribute,
                    "Changing the text size keeps the host grid and terminal modes")
        try require(requested.count == fitted + 1 && requested.last == fittingGrid() && requested[fitted].columns < requested[fitted - 1].columns,
                    "A larger text size requests fewer columns: \(requested)")
        let phoneGrid = requested[fitted]
        view.insertText("y")
        try require(requested.count == fitted + 1, "Typing never sends a grid: the Mac decides when typing claims it back: \(requested)")
        session.resendGrid()
        try require(requested.count == fitted + 2 && requested.last == phoneGrid, "A new stream re-sends the last requested grid")
        let viewport = ancestorViewport()!
        try require(abs(viewport.zoomScale - min(1, viewport.bounds.width / session.canvasSize.width)) < 0.01, "Terminal initially fits the phone width")
        viewport.setZoomScale(1.5, animated: false)
        view.layoutIfNeeded()
        try require(terminal.cols == 90 && terminal.rows == 35, "Zooming never changes the host grid")
        apply("", columns: 43, rows: 13)
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutIfNeeded()
        view.layoutIfNeeded()
        try require(terminal.cols == 43 && terminal.rows == 13 && terminal.applicationCursor, "Only a host resize changes the grid, preserving modes")
        try require(view.bounds.size == session.canvasSize, "A host resize resizes the canvas: \(view.bounds.size) \(session.canvasSize)")
        view.insertText("w")
        try await Task.sleep(for: .milliseconds(300))
        try require(requested.count == fitted + 2, "A host grid change alone never makes the phone request its grid again: \(requested)")
        return "PASS iOS emulator mode preservation\nPASS suppress mirrored replies and forward real keyboard input\nPASS host grid survives UIKit attachment, rotation and keyboard-sized viewports\nPASS host resize preserves modes\nPASS fit-to-width and zoom preserve the host grid\nPASS the phone requests the grid that fits its screen and text size, and re-sends it on a new stream"
    }
}
