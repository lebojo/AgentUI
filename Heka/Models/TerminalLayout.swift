import CoreGraphics
import Foundation

enum SplitAxis: String, Codable, Sendable {
    case horizontal, vertical
}

enum DropEdge: Sendable {
    case leading, trailing, top, bottom

    var axis: SplitAxis {
        switch self {
        case .leading, .trailing: .horizontal
        case .top, .bottom: .vertical
        }
    }

    var insertsBefore: Bool { self == .leading || self == .top }

    init(location: CGPoint, in size: CGSize) {
        let x = size.width > 0 ? min(max(location.x / size.width, 0), 1) : 0.5
        let y = size.height > 0 ? min(max(location.y / size.height, 0), 1) : 0.5
        let horizontal: DropEdge = x < 0.5 ? .leading : .trailing
        let vertical: DropEdge = y < 0.5 ? .top : .bottom
        self = min(x, 1 - x) <= min(y, 1 - y) ? horizontal : vertical
    }
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

    var axis: SplitAxis? {
        if case .split(let axis, _) = self { axis } else { nil }
    }

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
            return Self.normalised(axis, children.compactMap { $0.removing(id) })
        }
    }

    func inserting(_ id: UUID, beside target: UUID, edge: DropEdge) -> TerminalLayout {
        guard id != target, contains(target), !contains(id) else { return self }
        switch self {
        case .terminal:
            return .split(edge.axis, edge.insertsBefore ? [.terminal(id), self] : [self, .terminal(id)])
        case .split(let axis, var children):
            if axis == edge.axis, let index = children.firstIndex(of: .terminal(target)) {
                children.insert(.terminal(id), at: edge.insertsBefore ? index : index + 1)
                return .split(axis, children)
            }
            return Self.normalised(axis, children.map { $0.inserting(id, beside: target, edge: edge) }) ?? self
        }
    }

    func moving(_ id: UUID, beside target: UUID, edge: DropEdge) -> TerminalLayout {
        guard id != target, contains(target), let remaining = removing(id) else { return self }
        return remaining.inserting(id, beside: target, edge: edge)
    }

    private static func normalised(_ axis: SplitAxis, _ children: [TerminalLayout]) -> TerminalLayout? {
        let flattened = children.flatMap { child -> [TerminalLayout] in
            if case .split(axis, let grandchildren) = child { grandchildren } else { [child] }
        }
        return flattened.count > 1 ? .split(axis, flattened) : flattened.first
    }
}
