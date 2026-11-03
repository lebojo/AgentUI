import Foundation

indirect enum RepositoryImportItem: Identifiable, Equatable, Sendable {
    case folder(path: String, name: String, items: [RepositoryImportItem])
    case repository(path: String, name: String)

    var id: String {
        switch self {
        case .folder(let path, _, _): "folder:\(path)"
        case .repository(let path, _): "repository:\(path)"
        }
    }

    var path: String {
        switch self {
        case .folder(let path, _, _), .repository(let path, _): path
        }
    }

    var name: String {
        switch self {
        case .folder(_, let name, _), .repository(_, let name): name
        }
    }

    var children: [RepositoryImportItem]? {
        guard case .folder(_, _, let items) = self else { return nil }
        return items
    }

    var repositories: [RepositoryImportItem] {
        switch self {
        case .folder(_, _, let items): items.flatMap(\.repositories)
        case .repository: [self]
        }
    }

    var repositoryPaths: [String] { repositories.map(\.path) }

    func keeping(_ selection: Set<String>) -> RepositoryImportItem? {
        switch self {
        case .repository(let path, _):
            return selection.contains(path) ? self : nil
        case .folder(let path, let name, let items):
            let kept = items.compactMap { $0.keeping(selection) }
            if kept.isEmpty { return nil }
            if kept.count == 1, case .repository(path, _) = kept[0] { return kept[0] }
            return .folder(path: path, name: name, items: kept)
        }
    }

    static func tree(of repositories: [String], in root: String, named name: String) -> RepositoryImportItem {
        let inside = repositories.filter { $0.hasPrefix(root + "/") }
        let outside = repositories.filter { $0 != root && !$0.hasPrefix(root + "/") }
            .map { RepositoryImportItem.repository(path: $0, name: lastComponent(of: $0)) }
        let own = repositories.contains(root) ? [RepositoryImportItem.repository(path: root, name: name)] : []
        return .folder(path: root, name: name, items: own + items(of: inside, in: root) + outside)
    }

    private static func items(of repositories: [String], in directory: String) -> [RepositoryImportItem] {
        var groups: [(path: String, repositories: [String])] = []
        for repository in repositories {
            let component = repository.dropFirst(directory.count + 1).prefix { $0 != "/" }
            let path = directory + "/" + component
            if let index = groups.firstIndex(where: { $0.path == path }) {
                groups[index].repositories.append(repository)
            } else {
                groups.append((path, [repository]))
            }
        }
        return groups.map { group in
            let name = lastComponent(of: group.path)
            if group.repositories == [group.path] { return .repository(path: group.path, name: name) }
            let own = group.repositories.contains(group.path) ? [RepositoryImportItem.repository(path: group.path, name: name)] : []
            let nested = group.repositories.filter { $0 != group.path }
            return .folder(path: group.path, name: name, items: own + items(of: nested, in: group.path))
        }
    }

    private static func lastComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

struct RepositoryImport: Identifiable, Sendable {
    let id = UUID()
    let tree: RepositoryImportItem
    let repositoryPaths: [String]
    let targetFolderID: UUID?
    let destinationName: String
    let warning: String?
    private let hierarchyPreview: RepositoryImportItem
    private let flatPreview: RepositoryImportItem

    var needsReview: Bool { repositoryPaths.count > 1 }

    init(source: URL, discovery: RepositoryDiscoveryResult, target: ProjectFolder?) {
        let root = WorkspacePath.canonical(source)
        let tree = RepositoryImportItem.tree(of: discovery.repositories.map(\.path), in: root, named: source.lastPathComponent)
        let destinationName = target?.name ?? source.lastPathComponent
        self.tree = tree
        self.destinationName = destinationName
        repositoryPaths = tree.repositoryPaths
        targetFolderID = target?.id
        warning = discovery.warning
        hierarchyPreview = .folder(path: root, name: destinationName, items: tree.children ?? [])
        flatPreview = .folder(path: root, name: destinationName, items: tree.repositories)
    }

    func preview(flattened: Bool) -> RepositoryImportItem {
        flattened ? flatPreview : hierarchyPreview
    }
}
