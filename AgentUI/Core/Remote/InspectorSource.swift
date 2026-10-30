import Foundation

@MainActor protocol InspectorSource: Sendable {
    var canOpenLocalFiles: Bool { get }
    func openLocalFile(_ url: URL)
    func revealLocalFile(_ url: URL)
    func children(at url: URL) async throws -> [ExplorerEntry]
    func textFile(_ url: URL) async throws -> String
    func localGit(at path: String) async throws -> LocalGitSnapshot
    func remote(_ snapshot: LocalGitSnapshot) async throws -> RemoteSnapshot
    func diff(_ change: GitChange, at root: String) async throws -> GitDiff
    func conversations(at path: String, fresh: Bool) async throws -> [AgentConversation]
    func repositoryChanges(at path: String) async -> AsyncStream<Void>
    func conversationChanges() async -> AsyncStream<Void>
    func resume(_ conversation: AgentConversation, context: TerminalContext) async throws
}

extension InspectorSource {
    var canOpenLocalFiles: Bool { false }
    func openLocalFile(_ url: URL) {}
    func revealLocalFile(_ url: URL) {}
}
