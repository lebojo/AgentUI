import Foundation
import AppKit

@MainActor struct LocalInspectorSource: InspectorSource {
    let store: WorkspaceStore
    let settings: SettingsStore

    var canOpenLocalFiles: Bool { true }
    var canWriteRepository: Bool { true }
    func openLocalFile(_ url: URL) { NSWorkspace.shared.open(url) }
    func revealLocalFile(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func children(at url: URL) async throws -> ExplorerListing { ExplorerListing(entries: try await InspectorService.children(at: url)) }
    func textFile(_ url: URL) async throws -> String { try await InspectorService.textFile(url) }
    func localGit(at path: String) async throws -> LocalGitSnapshot { try await InspectorService.localGit(at: path) }
    func remote(_ snapshot: LocalGitSnapshot) async throws -> RemoteSnapshot {
        try await InspectorService.remote(for: snapshot)
    }
    func diff(_ change: GitChange, in scope: GitChangeScope, at root: String) async throws -> GitDiff {
        switch scope {
        case .staged: try await InspectorService.diff(change, at: root, including: [.staged])
        case .unstaged: try await InspectorService.diff(change, at: root, including: [.unstaged])
        case .branch(let base): try await InspectorService.comparisonDiff(change, base: base, at: root)
        }
    }
    func branches(at root: String) async throws -> GitBranchList { try await InspectorService.branches(at: root) }
    func comparison(with base: ComparisonBranch, at root: String) async throws -> BranchComparison {
        try await InspectorService.comparison(with: base, at: root)
    }
    func conversations(at path: String, fresh: Bool) async throws -> [AgentConversation] {
        await ConversationIndex.load(at: path, runningMaximumAge: fresh ? .zero : .seconds(10))
    }
    func repositoryChanges(at path: String) async -> AsyncStream<Void> { await FileEvents.repositoryChanges(at: path) }
    func conversationChanges() async -> AsyncStream<Void> {
        FileEvents.changes(in: ConversationIndex.watchedDirectories, latency: .seconds(1), every: .seconds(15))
    }
    func resume(_ conversation: AgentConversation, context: TerminalContext) async throws {
        try store.resume(conversation, projectID: context.project.id, worktreeID: context.worktree.id)
    }
    func perform(_ action: GitAction, at root: String) async throws { try await InspectorService.perform(action, at: root) }
    func runAgent(prompt: KeyPath<AgentPrompts, String>, name: String, context: TerminalContext) {
        guard let project = store.projects.first(where: { $0.id == context.project.id }),
              let worktree = project.worktrees.first(where: { $0.id == context.worktree.id }) else { return }
        store.runAgent(prompt: settings.prompts[keyPath: prompt], name: name, in: project, worktree, launch: settings.agentLaunch)
    }
}
