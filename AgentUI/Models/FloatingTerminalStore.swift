import AppKit
import Observation

@MainActor @Observable final class FloatingTerminalStore {
    private static let stateKey = "floatingTerminal.state"

    private(set) var state: FloatingTerminal {
        didSet { if !state.hasSameLayout(as: oldValue) { persist() } }
    }
    var isPresented = false {
        didSet { if !isPresented { persist() } }
    }
    private let sessions: TerminalSessions
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private let defaults: UserDefaults

    init(sessions: TerminalSessions, defaults: UserDefaults = .standard) {
        self.sessions = sessions
        self.defaults = defaults
        state = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(FloatingTerminal.self, from: $0) } ?? FloatingTerminal()
    }

    var isKey: Bool { window?.isKeyWindow == true }

    func attach(_ window: NSWindow?) {
        self.window = window
    }

    func prepare() {
        if state.isEmpty { openTab() }
    }

    func session(_ id: UUID) -> TerminalSession? { sessions.session(id) }

    func directory(of id: UUID) -> String {
        session(id)?.currentDirectory ?? state.pane(id)?.path ?? Self.homePath
    }

    func title(of id: UUID) -> String {
        let directory = directory(of: id)
        return directory == Self.homePath ? "~" : URL(filePath: directory, directoryHint: .isDirectory).lastPathComponent
    }

    func startSession(_ id: UUID) {
        guard let pane = state.pane(id) else { return }
        sessions.start(TerminalContext(floating: FloatingTerminal.Pane(id: pane.id, path: Self.existing(pane.path))))
    }

    func openTab() {
        state.addTab(path: Self.existing(state.focusedID.map(directory) ?? Self.homePath))
    }

    func split(_ axis: SplitAxis) {
        guard let focusedID = state.focusedID else { return openTab() }
        state.split(focusedID, axis: axis, path: Self.existing(directory(of: focusedID)))
    }

    func focus(_ id: UUID) {
        guard state.focusedID != id else { return }
        state.focus(id)
    }

    func select(_ tab: TerminalLayout) {
        state.select(tab)
    }

    func selectTab(offset: Int) {
        state.selectTab(offset: offset)
    }

    func reopen(_ id: UUID) {
        sessions.close(id)
        startSession(id)
    }

    func close(_ id: UUID) {
        sessions.close(id)
        state.close(id)
        if state.isEmpty { isPresented = false }
    }

    func close(_ tab: TerminalLayout) {
        for id in tab.terminalIDs { close(id) }
    }

    func closeFocused() {
        if let focusedID = state.focusedID { close(focusedID) } else { isPresented = false }
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    private static func existing(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : homePath
    }
}
