import Foundation

struct SidebarTerminalBlock: Identifiable, Equatable, Sendable {
    let terminals: [TerminalRecord]
    var axis: SplitAxis? = nil

    var id: UUID { terminals[0].id }
    var isSplit: Bool { terminals.count > 1 }
    var terminalIDs: [UUID] { terminals.map(\.id) }
    var singleTerminal: TerminalRecord? { isSplit ? nil : terminals[0] }

    func contains(_ id: UUID?) -> Bool { terminals.contains { $0.id == id } }
    func selectionTag(for selection: UUID?) -> UUID { terminals.first { $0.id == selection }?.id ?? id }
}

extension Worktree {
    func terminalBlocks(showing visible: [TerminalRecord]) -> [SidebarTerminalBlock] {
        let records = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let layoutByTerminal = layoutsByTerminal()
        var placed: Set<UUID> = []
        var blocks: [SidebarTerminalBlock] = []
        for terminal in visible where !placed.contains(terminal.id) {
            guard let layout = layoutByTerminal[terminal.id], layout.isSplit else {
                placed.insert(terminal.id)
                blocks.append(SidebarTerminalBlock(terminals: [terminal]))
                continue
            }
            let members = layout.terminalIDs.compactMap { placed.contains($0) ? nil : records[$0] }
            placed.formUnion(members.map(\.id))
            blocks.append(SidebarTerminalBlock(terminals: members, axis: members.count > 1 ? layout.axis : nil))
        }
        return blocks
    }

    private func layoutsByTerminal() -> [UUID: TerminalLayout] {
        var result: [UUID: TerminalLayout] = [:]
        for layout in layouts {
            for id in layout.terminalIDs where result[id] == nil { result[id] = layout }
        }
        return result
    }
}

extension [SidebarTerminalBlock] {
    var terminalIDs: [UUID] { flatMap(\.terminalIDs) }

    func reordering(_ terminals: [TerminalRecord], from source: IndexSet, to destination: Int) -> [TerminalRecord]? {
        guard let order = moving(map(\.id), from: source, to: destination)?.terminalIDs, order != terminalIDs else { return nil }
        let visible = Set(order)
        let records = Dictionary(terminals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var slots = order.compactMap { records[$0] }.makeIterator()
        return terminals.map { visible.contains($0.id) ? slots.next() ?? $0 : $0 }
    }

    func reordering(_ terminals: [TerminalRecord], moving terminalID: UUID, to destination: Int) -> [TerminalRecord]? {
        guard let source = firstIndex(where: { $0.contains(terminalID) }) else { return nil }
        return reordering(terminals, from: [source], to: destination)
    }
}
