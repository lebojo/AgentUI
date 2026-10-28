import Foundation
import SQLite3

enum OpenCodeSessions {
    struct Session: Equatable, Sendable {
        let id: String
        let directory: String
        let title: String?
        let updatedAt: Date
    }

    static func read(_ database: URL) -> [Session]? {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(connection, 100)
        var sessions: [Session] = []
        for table in ["session", "session_v2"] {
            guard let found = Self.sessions(in: table, of: connection) else { return nil }
            sessions += found
        }
        return sessions
    }

    private static func sessions(in table: String, of connection: OpaquePointer?) -> [Session]? {
        guard let columns = rows("PRAGMA table_info(\(table))", in: connection, { text($0, 1) }).map(Set.init) else { return nil }
        guard columns.isSuperset(of: ["id", "directory", "time_updated"]) else { return [] }
        let title = columns.contains("title") ? "title" : "NULL"
        let filters = ["parent_id", "time_archived"].filter(columns.contains).map { "\($0) IS NULL" }
        let query = "SELECT id, directory, time_updated, \(title) FROM \(table)" + (filters.isEmpty ? "" : " WHERE " + filters.joined(separator: " AND "))
        return rows(query, in: connection) { statement in
            guard let id = text(statement, 0), let directory = text(statement, 1) else { return nil }
            let updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1000)
            return Session(id: id, directory: directory, title: text(statement, 3), updatedAt: updatedAt)
        }
    }

    private static func rows<Row>(_ query: String, in connection: OpaquePointer?, _ row: (OpaquePointer?) -> Row?) -> [Row]? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        var found: [Row] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let value = row(statement) { found.append(value) }
            status = sqlite3_step(statement)
        }
        return status == SQLITE_DONE ? found : nil
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}
