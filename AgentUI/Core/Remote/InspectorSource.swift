import Foundation

@MainActor protocol InspectorSource: Sendable {
    var canOpenLocalFiles: Bool { get }
    var canWriteRepository: Bool { get }
    func openLocalFile(_ url: URL)
    func revealLocalFile(_ url: URL)
    func children(at url: URL) async throws -> ExplorerListing
    func textFile(_ url: URL) async throws -> String
    func localGit(at path: String) async throws -> LocalGitSnapshot
    func remote(_ snapshot: LocalGitSnapshot) async throws -> RemoteSnapshot
    func diff(_ change: GitChange, in scope: GitChangeScope, at root: String) async throws -> GitDiff
    func branches(at root: String) async throws -> GitBranchList
    func comparison(with base: ComparisonBranch, at root: String) async throws -> BranchComparison
    func conversations(at path: String, fresh: Bool) async throws -> [AgentConversation]
    func repositoryChanges(at path: String) async -> AsyncStream<Void>
    func conversationChanges() async -> AsyncStream<Void>
    func resume(_ conversation: AgentConversation, context: TerminalContext) async throws
    func perform(_ action: GitAction, at root: String) async throws
    func runAgent(prompt: KeyPath<AgentPrompts, String>, name: String, in worktree: InspectedWorktree)
}

extension InspectorSource {
    var canOpenLocalFiles: Bool { false }
    func openLocalFile(_ url: URL) {}
    func revealLocalFile(_ url: URL) {}
    var canWriteRepository: Bool { false }
    func perform(_ action: GitAction, at root: String) async throws { throw CocoaError(.featureUnsupported) }
    func runAgent(prompt: KeyPath<AgentPrompts, String>, name: String, in worktree: InspectedWorktree) {}
}
