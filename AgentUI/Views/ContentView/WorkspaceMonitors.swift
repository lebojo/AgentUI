import SwiftUI

struct WorkspaceMonitors: ViewModifier {
    private struct RepositoryWatch: Equatable {
        let worktreePaths: [String]
        let isVisible: Bool
    }

    private struct WorktreeFolderWatch: Equatable {
        let creationDirectory: URL
        let directories: [URL]
        let isVisible: Bool
    }

    private struct WorktreeFolderScan: Equatable {
        let directories: [URL]
        let knownPaths: [String]
        let isVisible: Bool
    }

    @Environment(AppVisibility.self) private var visibility
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage

    let store: WorkspaceStore
    let gitActionQueues: GitActionQueues

    private var repositoryWatch: RepositoryWatch {
        RepositoryWatch(worktreePaths: store.projects.flatMap(\.worktrees).map(\.path), isVisible: visibility.isVisible)
    }

    private var worktreeFolderWatch: WorktreeFolderWatch {
        WorktreeFolderWatch(creationDirectory: settings.creationWorktreesDirectory,
                            directories: settings.watchedWorktreesDirectories, isVisible: visibility.isVisible)
    }
    private var worktreeFolderScan: WorktreeFolderScan {
        let projects = store.projects
        return WorktreeFolderScan(directories: settings.watchedWorktreesDirectories,
                                  knownPaths: projects.map(\.path) + projects.flatMap(\.worktrees).map(\.path),
                                  isVisible: visibility.isVisible)
    }

    func body(content: Content) -> some View {
        content
            .task(id: repositoryWatch, priority: .utility) { await watchRepositories(repositoryWatch) }
            .task(id: worktreeFolderWatch, priority: .utility) { await watchWorktreeFolders(worktreeFolderWatch) }
            .task(id: worktreeFolderScan, priority: .utility) {
                guard worktreeFolderScan.isVisible else { return }
                await store.adoptWorktrees(in: worktreeFolderScan.directories)
            }
            .task(id: visibility.isVisible, priority: .utility) {
                guard visibility.isVisible else { return }
                await usage.monitor()
            }
            .task(id: visibility.isVisible, priority: .utility) {
                guard visibility.isVisible else { return }
                await watchConversationTitles()
            }
            .task(id: visibility.isVisible, priority: .utility) {
                guard visibility.isVisible else { return }
                await store.sessions.watchAgents()
            }
    }

    private func watchRepositories(_ watch: RepositoryWatch) async {
        gitActionQueues.prune(keepingRootsOf: watch.worktreePaths)
        await GitRootCache.shared.prune(keepingPathsIn: watch.worktreePaths)
        guard watch.isVisible else { return }
        let repositories = await GitRepository.repositories(containing: watch.worktreePaths)
        let metadata = Array(Set(repositories.map(\.commonDirectory.path)))
        for await _ in FileEvents.changes(in: metadata, latency: .milliseconds(300), every: .seconds(2)) {
            await store.sessions.refreshRepositories(worktreePaths: watch.worktreePaths)
        }
    }

    private func watchWorktreeFolders(_ watch: WorktreeFolderWatch) async {
        guard watch.isVisible else { return }
        try? FileManager.default.createDirectory(at: watch.creationDirectory, withIntermediateDirectories: true)
        for await _ in FileEvents.entries(of: watch.directories, every: .seconds(30)).dropFirst() {
            await store.adoptWorktrees(in: watch.directories)
        }
    }

    private func watchConversationTitles() async {
        while !Task.isCancelled {
            store.applyConversationTitles(await store.sessions.conversationTitles())
            do { try await Task.sleep(for: .seconds(5)) }
            catch { break }
        }
    }
}
