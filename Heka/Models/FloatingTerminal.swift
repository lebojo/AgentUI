import Foundation

struct FloatingTerminal: Codable, Equatable, Sendable {
    struct Pane: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        var path: String
    }

    struct Tab: Identifiable, Codable, Equatable, Sendable {
        private enum CodingKeys: String, CodingKey { case id, layout }

        var id: UUID
        var layout: TerminalLayout

        init(id: UUID = UUID(), layout: TerminalLayout) {
            self.id = id
            self.layout = layout
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try container.decodeIfPresent(UUID.self, forKey: .id) {
                self.init(id: id, layout: try container.decode(TerminalLayout.self, forKey: .layout))
            } else {
                self.init(layout: try TerminalLayout(from: decoder))
            }
        }
    }

    static let projectID = UUID(uuidString: "6F1D2C8E-4B7A-4E0F-9C55-0A3B7E2D9F10")!
    static let worktreeID = UUID(uuidString: "B84E1A27-93C6-4D58-8F02-61E5C9A7D3B4")!

    private(set) var panes: [Pane] = []
    private(set) var tabs: [Tab] = []
    private(set) var focusHistory: [UUID] = []

    var isEmpty: Bool { tabs.isEmpty }
    var focusedID: UUID? { focusHistory.first { pane($0) != nil } ?? tabs.first?.layout.id }
    var selectedTab: Tab? {
        guard let focusedID else { return nil }
        return tabs.first { $0.layout.contains(focusedID) }
    }

    func pane(_ id: UUID) -> Pane? { panes.first { $0.id == id } }

    func hasSameLayout(as other: FloatingTerminal) -> Bool {
        panes == other.panes && tabs == other.tabs
    }

    func focusedID(in tab: Tab) -> UUID {
        focusHistory.first(where: tab.layout.contains) ?? tab.layout.id
    }

    @discardableResult mutating func addTab(path: String) -> Pane {
        let pane = Pane(path: path)
        panes.append(pane)
        tabs.append(Tab(layout: .terminal(pane.id)))
        focus(pane.id)
        return pane
    }

    @discardableResult mutating func split(_ id: UUID, axis: SplitAxis, path: String) -> Pane? {
        guard let index = tabs.firstIndex(where: { $0.layout.contains(id) }) else { return nil }
        let pane = Pane(path: path)
        panes.append(pane)
        tabs[index].layout = tabs[index].layout.splitting(id, with: pane.id, axis: axis)
        focus(pane.id)
        return pane
    }

    mutating func focus(_ id: UUID) {
        guard pane(id) != nil else { return }
        focusHistory.removeAll { $0 == id }
        focusHistory.insert(id, at: 0)
    }

    mutating func select(_ tab: Tab) {
        focus(focusedID(in: tab))
    }

    mutating func selectTab(offset: Int) {
        guard let selectedTab, let index = tabs.firstIndex(of: selectedTab) else { return }
        let count = tabs.count
        select(tabs[((index + offset) % count + count) % count])
    }

    mutating func close(_ id: UUID) {
        let neighbour = tabs.first { $0.layout.contains(id) }?.layout.neighbour(of: id)
        let wasFocused = focusedID == id
        panes.removeAll { $0.id == id }
        tabs = tabs.compactMap { tab in tab.layout.removing(id).map { Tab(id: tab.id, layout: $0) } }
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
