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
                InspectorNotice(title: "Conversations indisponibles", message: error)
            } else if conversations != nil {
                ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Les conversations Claude, Codex, Copilot et OpenCode lancées dans ce dossier apparaîtront ici."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(refresh)-\(scenePhase == .background)-\(workspaceVisible)", priority: .utility) {
            guard workspaceVisible, scenePhase != .background else { return }
            await monitor()
        }
        .alert("Reprise impossible", isPresented: $resumeError.isPresent) {
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
