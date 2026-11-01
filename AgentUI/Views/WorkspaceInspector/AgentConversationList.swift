import SwiftUI

struct AgentConversationList: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.workspaceVisible) private var workspaceVisible

    @State private var conversations: [AgentConversation]?
    @State private var error: String?
    @State private var resumeError: String?

    let context: TerminalContext
    let refresh: Int
    let source: any InspectorSource

    var body: some View {
        Group {
            if let conversations, !conversations.isEmpty {
                List(conversations) { conversation in
                    AgentConversationRow(conversation: conversation) { resume(conversation) }
                }.listStyle(.plain)
            } else if let error {
                InspectorNotice(title: "Conversations Unavailable", message: error)
            } else if conversations != nil {
                ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Claude, Codex, Copilot and OpenCode conversations started in this folder will appear here."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(refresh)-\(scenePhase == .background)-\(workspaceVisible)", priority: .utility) {
            guard workspaceVisible, scenePhase != .background else { return }
            await monitor()
        }
        .alert("Couldn’t Resume", isPresented: $resumeError.isPresent) {
            Button("OK") { resumeError = nil }
        } message: { Text(resumeError ?? "") }
    }

    private func monitor() async {
        var fresh = true
        for await _ in await source.conversationChanges() {
            do {
                let found = try await source.conversations(at: context.worktree.path, fresh: fresh)
                fresh = false
                guard !Task.isCancelled else { return }
                if conversations != found { conversations = found }
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func resume(_ conversation: AgentConversation) {
        Task {
            do { try await source.resume(conversation, context: context) }
            catch { resumeError = error.localizedDescription }
        }
    }
}
