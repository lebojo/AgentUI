import Foundation

struct FloatingTerminal: Codable, Equatable, Sendable {
    struct Pane: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        var path: String
    }

    static let projectID = UUID(uuidString: "6F1D2C8E-4B7A-4E0F-9C55-0A3B7E2D9F10")!
    static let worktreeID = UUID(uuidString: "B84E1A27-93C6-4D58-8F02-61E5C9A7D3B4")!

    private(set) var panes: [Pane] = []
    private(set) var tabs: [TerminalLayout] = []
    private(set) var focusHistory: [UUID] = []

    var isEmpty: Bool { tabs.isEmpty }
    var focusedID: UUID? { focusHistory.first { pane($0) != nil } ?? tabs.first?.id }
    var selectedTab: TerminalLayout? {
        guard let focusedID else { return nil }
        return tabs.first { $0.contains(focusedID) }
    }

    func pane(_ id: UUID) -> Pane? { panes.first { $0.id == id } }

    func hasSameLayout(as other: FloatingTerminal) -> Bool {
        panes == other.panes && tabs == other.tabs
    }

    func focusedID(in tab: TerminalLayout) -> UUID {
        focusHistory.first(where: tab.contains) ?? tab.id
    }

    @discardableResult mutating func addTab(path: String) -> Pane {
        let pane = Pane(path: path)
        panes.append(pane)
        tabs.append(.terminal(pane.id))
        focus(pane.id)
        return pane
    }

    @discardableResult mutating func split(_ id: UUID, axis: SplitAxis, path: String) -> Pane? {
        guard let index = tabs.firstIndex(where: { $0.contains(id) }) else { return nil }
        let pane = Pane(path: path)
        panes.append(pane)
        tabs[index] = tabs[index].splitting(id, with: pane.id, axis: axis)
        focus(pane.id)
        return pane
    }

    mutating func focus(_ id: UUID) {
        guard pane(id) != nil else { return }
        focusHistory.removeAll { $0 == id }
        focusHistory.insert(id, at: 0)
    }

    mutating func select(_ tab: TerminalLayout) {
        focus(focusedID(in: tab))
    }

    mutating func selectTab(offset: Int) {
        guard let selectedTab, let index = tabs.firstIndex(of: selectedTab) else { return }
        let count = tabs.count
        select(tabs[((index + offset) % count + count) % count])
    }

    mutating func close(_ id: UUID) {
        let neighbour = tabs.first { $0.contains(id) }?.neighbour(of: id)
        let wasFocused = focusedID == id
        panes.removeAll { $0.id == id }
        tabs = tabs.compactMap { $0.removing(id) }
        focusHistory.removeAll { $0 == id }
        if wasFocused, let neighbour { focus(neighbour) }
    }
}

extension TerminalContext {
    init(floating pane: FloatingTerminal.Pane) {
        project = ProjectInfo(id: FloatingTerminal.projectID, name: String(localized: "Floating Terminal"))
        worktree = WorktreeInfo(id: FloatingTerminal.worktreeID, name: pane.path, path: pane.path, isPrimary: true)
        terminal = TerminalRecord(id: pane.id, name: TerminalRecord.defaultName)
    }

    var isFloating: Bool { project.id == FloatingTerminal.projectID }
}
