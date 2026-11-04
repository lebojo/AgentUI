import Foundation

struct SidebarTerminalBlock: Identifiable, Equatable, Sendable {
    let terminals: [TerminalRecord]
    var axis: SplitAxis? = nil

    var id: UUID { terminals[0].id }
    var isSplit: Bool { terminals.count > 1 }

    func contains(_ id: UUID?) -> Bool { terminals.contains { $0.id == id } }
}

extension Worktree {
    func terminalBlocks(showing visible: [TerminalRecord]) -> [SidebarTerminalBlock] {
        var placed: Set<UUID> = []
        var blocks: [SidebarTerminalBlock] = []
        for terminal in visible where !placed.contains(terminal.id) {
            guard let layout = layout(containing: terminal.id), layout.isSplit else {
                placed.insert(terminal.id)
                blocks.append(SidebarTerminalBlock(terminals: [terminal]))
                continue
            }
            let members = layout.terminalIDs.compactMap { id in visible.first { $0.id == id && !placed.contains(id) } }
            placed.formUnion(members.map(\.id))
            blocks.append(SidebarTerminalBlock(terminals: members, axis: members.count > 1 ? layout.axis : nil))
        }
        return blocks
    }
}

extension [SidebarTerminalBlock] {
    var terminalIDs: [UUID] { flatMap { $0.terminals.map(\.id) } }

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
