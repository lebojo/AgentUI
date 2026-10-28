import SwiftUI

struct AgentConversationList: View {
    @State private var conversations: [AgentConversation]?
    @Bindable var store: WorkspaceStore
    let context: TerminalContext
    let refresh: Int

    var body: some View {
        Group {
            if let conversations, !conversations.isEmpty {
                List(conversations) { conversation in
                    AgentConversationRow(conversation: conversation) { resume(conversation) }
                }.listStyle(.plain)
            } else if conversations != nil {
                ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Les conversations Claude et Codex lancées dans ce dossier apparaîtront ici."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: refresh) { await monitor() }
    }

    private func monitor() async {
        while !Task.isCancelled {
            let found = await ConversationIndex.load(at: context.worktree.path)
            guard !Task.isCancelled else { return }
            if conversations != found { conversations = found }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    private func resume(_ conversation: AgentConversation) {
        let name = conversation.title.count > 40 ? String(conversation.title.prefix(39)) + "…" : conversation.title
        do {
            _ = try store.addTerminal(projectID: context.project.id, worktreeID: context.worktree.id,
                                      name: name, command: conversation.resumeCommand)
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct AgentConversationRow: View {
    let conversation: AgentConversation
    let resume: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            conversation.agent.logo
                .resizable()
                .scaledToFit()
                .frame(width: IconSize.s, height: IconSize.s)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(conversation.title).lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    Text(conversation.agent.title)
                    Text("·")
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                    if conversation.isRunning {
                        Text("·")
                        Text("En cours").foregroundStyle(Palette.success)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xs)
            Button(action: resume) { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .disabled(conversation.isRunning)
                .help(conversation.isRunning ? "Cette conversation est déjà ouverte" : "Reprendre dans un nouveau terminal")
                .accessibilityLabel("Reprendre \(conversation.title)")
        }
        .padding(.vertical, Spacing.xxs)
    }
}

private extension ConversationAgent {
    var logo: Image {
        switch self {
        case .claude: Image(.claudeLogo)
        case .codex: Image(.codexLogo)
        }
    }
}
