import Foundation

struct SidebarTerminalBlock: Identifiable, Equatable, Sendable {
    let terminals: [TerminalRecord]
    var axis: SplitAxis? = nil

    var id: UUID { terminals[0].id }
    var isSplit: Bool { terminals.count > 1 }

    func contains(_ id: UUID?) -> Bool { terminals.contains { $0.id == id } }
}

struct SidebarTerminalMove: Equatable, Sendable {
    let source: IndexSet
    let destination: Int
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

    func terminalMove(from source: IndexSet, to destination: Int) -> SidebarTerminalMove {
        let starts = reduce(into: [0]) { result, block in result.append(result[result.count - 1] + block.terminals.count) }
        let terminals = source.filter(indices.contains).reduce(into: IndexSet()) { result, block in
            result.insert(integersIn: starts[block]..<starts[block + 1])
        }
        return SidebarTerminalMove(source: terminals, destination: starts[Swift.min(Swift.max(destination, 0), count)])
    }
}
