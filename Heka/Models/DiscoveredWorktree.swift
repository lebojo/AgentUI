import Foundation

struct DiscoveredWorktree: Identifiable, Equatable, Sendable {
    let path: String
    let branch: String?
    let repositoryPath: String?
    let hasRepository: Bool

    init(path: String, branch: String?, repositoryPath: String?) {
        self.path = path
        self.branch = branch
        self.repositoryPath = repositoryPath
        hasRepository = repositoryPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    var id: String { path }
    var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
    var repositoryName: String? { repositoryPath.map { URL(fileURLWithPath: $0).lastPathComponent } }
}
