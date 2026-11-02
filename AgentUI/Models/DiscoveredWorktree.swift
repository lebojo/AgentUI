import Foundation

struct DiscoveredWorktree: Identifiable, Equatable, Sendable {
    let path: String
    let branch: String?
    let repositoryPath: String?

    var id: String { path }
    var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
    var repositoryName: String? { repositoryPath.map { URL(fileURLWithPath: $0).lastPathComponent } }
    var hasRepository: Bool { repositoryPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }
}
