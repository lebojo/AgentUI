import Foundation

enum SplitAxis: String, Codable, Sendable {
    case horizontal, vertical
}

indirect enum TerminalLayout: Codable, Equatable, Identifiable, Sendable {
    case terminal(UUID)
    case split(SplitAxis, [TerminalLayout])

    var id: UUID { terminalIDs[0] }

    var terminalIDs: [UUID] {
        switch self {
        case .terminal(let id): [id]
        case .split(_, let children): children.flatMap(\.terminalIDs)
        }
    }

    var isSplit: Bool { terminalIDs.count > 1 }

    func contains(_ id: UUID) -> Bool { terminalIDs.contains(id) }

    func neighbour(of id: UUID) -> UUID? {
        let ids = terminalIDs
        guard let index = ids.firstIndex(of: id) else { return nil }
        return index > 0 ? ids[index - 1] : ids.dropFirst().first
    }

    func splitting(_ id: UUID, with newID: UUID, axis: SplitAxis) -> TerminalLayout {
        switch self {
        case .terminal(let current):
            return current == id ? .split(axis, [self, .terminal(newID)]) : self
        case .split(let current, var children):
            if current == axis, let index = children.firstIndex(of: .terminal(id)) {
                children.insert(.terminal(newID), at: index + 1)
                return .split(current, children)
            }
            return .split(current, children.map { $0.splitting(id, with: newID, axis: axis) })
        }
    }

    func removing(_ id: UUID) -> TerminalLayout? {
        switch self {
        case .terminal(let current):
            return current == id ? nil : self
        case .split(let axis, let children):
            let remaining = children.compactMap { $0.removing(id) }
            return remaining.count > 1 ? .split(axis, remaining) : remaining.first
        }
    }
}
