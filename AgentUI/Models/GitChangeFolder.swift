import Foundation

struct GitChangeFolder: Equatable, Sendable {
    let path: String
    let name: String
    let folders: [GitChangeFolder]
    let files: [GitChange]
    let count: Int

    var rows: [GitChangeTreeRow] {
        var rows: [GitChangeTreeRow] = []
        rows.reserveCapacity(count)
        appendRows(to: &rows, depth: 0)
        return rows
    }

    init(path: String, name: String, folders: [GitChangeFolder] = [], files: [GitChange] = []) {
        self.path = path
        self.name = name
        self.folders = folders
        self.files = files
        count = files.count + folders.reduce(0) { $0 + $1.count }
    }

    init(changes: [GitChange]) {
        var root = Node()
        for change in changes { root.insert(change, in: change.directories[...]) }
        self = root.folder(path: "", name: "")
    }

    private func appendRows(to rows: inout [GitChangeTreeRow], depth: Int) {
        for folder in folders {
            rows.append(GitChangeTreeRow(content: .folder(path: folder.path, name: folder.name), depth: depth))
            folder.appendRows(to: &rows, depth: depth + 1)
        }
        rows.append(contentsOf: files.map { GitChangeTreeRow(content: .file($0), depth: depth) })
    }

    private struct Node {
        var folders: [String: Node] = [:]
        var files: [GitChange] = []

        mutating func insert(_ change: GitChange, in directories: ArraySlice<String>) {
            if let first = directories.first {
                folders[first, default: Node()].insert(change, in: directories.dropFirst())
            } else {
                files.append(change)
            }
        }

        func folder(path: String, name: String) -> GitChangeFolder {
            let children = folders.map { key, node in node.compacted(path: path.isEmpty ? key : path + "/" + key, name: key) }
            return GitChangeFolder(path: path, name: name,
                                   folders: children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                                   files: files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }

        private func compacted(path: String, name: String) -> GitChangeFolder {
            var node = self, path = path, name = name
            while node.files.isEmpty, node.folders.count == 1, let (key, child) = node.folders.first {
                path += "/" + key
                name += "/" + key
                node = child
            }
            return node.folder(path: path, name: name)
        }
    }
}

struct GitChangeTreeRow: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case folder(path: String, name: String)
        case file(GitChange)
    }

    enum ID: Hashable, Sendable {
        case folder(String)
        case file(String)
    }

    let content: Content
    let depth: Int

    var id: ID {
        switch content {
        case .folder(let path, _): .folder(path)
        case .file(let change): .file(change.path)
        }
    }

    var folderPath: String? {
        guard case .folder(let path, _) = content else { return nil }
        return path
    }
}

struct GitChangeOutline: Equatable, Sendable {
    static let empty = GitChangeOutline(changes: [])

    let rows: [GitChangeTreeRow]
    let count: Int

    var isEmpty: Bool { count == 0 }

    init(changes: [GitChange]) {
        let tree = GitChangeFolder(changes: changes)
        rows = tree.rows
        count = tree.count
    }

    @concurrent static func build(_ changes: [GitChange]) async -> GitChangeOutline {
        GitChangeOutline(changes: changes)
    }

    func rows(collapsing collapsed: Set<String>) -> [GitChangeTreeRow] {
        guard !collapsed.isEmpty else { return rows }
        var visible: [GitChangeTreeRow] = []
        var collapsedDepth: Int?
        for row in rows {
            if let depth = collapsedDepth, row.depth > depth { continue }
            visible.append(row)
            collapsedDepth = row.folderPath.flatMap { collapsed.contains($0) ? row.depth : nil }
        }
        return visible
    }
}

struct GitChangeTrees: Equatable, Sendable {
    var staged = GitChangeOutline.empty
    var unstaged = GitChangeOutline.empty

    @concurrent static func build(_ snapshot: LocalGitSnapshot) async -> GitChangeTrees {
        GitChangeTrees(staged: GitChangeOutline(changes: snapshot.stagedChanges), unstaged: GitChangeOutline(changes: snapshot.unstagedChanges))
    }
}
