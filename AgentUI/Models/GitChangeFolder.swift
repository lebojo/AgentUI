import Foundation

struct GitChangeFolder: Identifiable, Equatable, Sendable {
    static let empty = GitChangeFolder(path: "", name: "")

    let path: String
    let name: String
    let folders: [GitChangeFolder]
    let files: [GitChange]
    let count: Int

    var id: String { path }
    var isEmpty: Bool { count == 0 }

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

    @concurrent static func build(_ changes: [GitChange]) async -> GitChangeFolder {
        GitChangeFolder(changes: changes)
    }

    func rows(collapsing collapsed: Set<String>) -> [GitChangeTreeRow] {
        var rows: [GitChangeTreeRow] = []
        rows.reserveCapacity(count)
        appendRows(to: &rows, depth: 0, collapsed: collapsed)
        return rows
    }

    private func appendRows(to rows: inout [GitChangeTreeRow], depth: Int, collapsed: Set<String>) {
        for folder in folders {
            rows.append(GitChangeTreeRow(content: .folder(path: folder.path, name: folder.name), depth: depth))
            if !collapsed.contains(folder.path) { folder.appendRows(to: &rows, depth: depth + 1, collapsed: collapsed) }
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

    let content: Content
    let depth: Int

    var id: String {
        switch content {
        case .folder(let path, _): "folder:" + path
        case .file(let change): "file:" + change.path
        }
    }
}

struct GitChangeTrees: Equatable, Sendable {
    var staged = GitChangeFolder.empty
    var unstaged = GitChangeFolder.empty

    @concurrent static func build(_ snapshot: LocalGitSnapshot) async -> GitChangeTrees {
        GitChangeTrees(staged: GitChangeFolder(changes: snapshot.stagedChanges), unstaged: GitChangeFolder(changes: snapshot.unstagedChanges))
    }
}
