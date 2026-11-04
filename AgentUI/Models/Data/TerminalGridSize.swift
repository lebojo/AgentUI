import Foundation

struct TerminalGridSize: Codable, Hashable, Sendable {
    static let columnRange = 20...400
    static let rowRange = 5...200

    let columns: Int
    let rows: Int

    init(columns: Int, rows: Int) {
        self.columns = min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        self.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(columns: container.decode(Int.self, forKey: .columns), rows: container.decode(Int.self, forKey: .rows))
    }
}
