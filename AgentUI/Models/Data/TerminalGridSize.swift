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

    func frameSize(scaling frame: CGSize, columns currentColumns: Int, rows currentRows: Int, scrollerWidth: CGFloat) -> CGSize? {
        guard currentColumns > 0, currentRows > 0 else { return nil }
        let cellWidth = (frame.width - scrollerWidth) / CGFloat(currentColumns)
        let cellHeight = frame.height / CGFloat(currentRows)
        guard cellWidth > 2, cellHeight > 2 else { return nil }
        return CGSize(width: ceil(cellWidth * (CGFloat(columns) + 0.5) + scrollerWidth),
                      height: ceil(cellHeight * (CGFloat(rows) + 0.5)))
    }
}
