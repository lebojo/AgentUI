import SwiftUI

struct WorkspaceMonitors: ViewModifier {
    private struct RepositoryWatch: Equatable {
        let worktreePaths: [String]
        let isVisible: Bool
    }

    @Environment(AppVisibility.self) private var visibility
    @Environment(UsageStore.self) private var usage

    let store: WorkspaceStore

    private var repositoryWatch: RepositoryWatch {
        RepositoryWatch(worktreePaths: store.projects.flatMap(\.worktrees).map(\.path), isVisible: visibility.isVisible)
    }

    func body(content: Content) -> some View {
        content
            .task(id: repositoryWatch, priority: .utility) { await watchRepositories(repositoryWatch) }
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
                await watchAgents()
            }
    }

    private func watchRepositories(_ watch: RepositoryWatch) async {
        guard watch.isVisible else { return }
        let repositories = await GitRepository.repositories(containing: watch.worktreePaths)
        let metadata = Array(Set(repositories.map(\.commonDirectory.path)))
        for await _ in FileEvents.changes(in: metadata, latency: .milliseconds(300), every: .seconds(2)) {
            await store.sessions.refreshRepositories(worktreePaths: watch.worktreePaths)
        }
    }

    private func watchAgents() async {
        while !Task.isCancelled {
            await store.sessions.refreshAgents()
            do { try await Task.sleep(for: .seconds(1)) }
            catch { break }
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
