import SwiftUI

struct MobileSessionDetail: View {
    let mode: SessionDisplayMode
    let store: MobileWorkspaceStore
    let showSettings: () -> Void

    var body: some View {
        Group {
            if let context = store.context {
                VStack(spacing: 0) {
                    MobileSessionHeader(project: context.project.name, worktree: context.worktree.name,
                                        agent: store.terminalAgents[context.terminal.id])
                    Divider()
                    if let session = store.session {
                        if session.isChat {
                            SessionChatView(messages: session.messages, source: session.chatSource, isEnabled: store.isConnected && !session.hasExited) { text in
                                try await store.input(Data((text + "\r").utf8), terminal: context.terminal.id, message: text)
                            } control: { data in
                                try await store.input(data, terminal: context.terminal.id)
                            }
                            .id(context.terminal.id)
                        } else if let terminal = session.view {
                            MobileTerminalViewport(terminal: terminal, canvasSize: session.canvasSize)
                            .id(session.identity)
                            .disabled(!store.isConnected || session.hasExited)
                            if mode == .chat, store.isConnected, !session.hasExited, !store.installedAgents.isEmpty {
                                AgentShortcutBar(agents: store.installedAgents) { agent in
                                    Task { await store.launch(agent, in: context) }
                                }
                            }
                        } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                        if session.hasExited {
                            SessionExitLabel(code: session.exitCode).font(Typography.caption).padding(Spacing.s)
                        }
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    if !store.isConnected {
                        Button(store.statusText, action: showSettings).font(Typography.caption).padding()
                    }
                }
                .navigationTitle(context.terminal.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Réglages", systemImage: "gearshape", action: showSettings)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Nouveau terminal", systemImage: "plus") { Task { await store.newTerminal(in: context) } }
                            .disabled(!store.isConnected)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(store.isConnected ? "Choisis un terminal" : "Continue sur ton Mac", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text(store.isConnected ? "Retrouve tes projets et tes sessions dans la barre latérale." : "Connecte-toi au Mac depuis les réglages pour retrouver tes projets et tes sessions.")
                } actions: {
                    Button("Réglages de connexion", action: showSettings).buttonStyle(.borderedProminent)
                }
                .navigationTitle("AgentUI")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MobileSessionHeader: View {
    let project: String
    let worktree: String
    let agent: ConversationAgent?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Label(project, systemImage: "shippingbox")
            Image(systemName: "chevron.right")
            Label(worktree, systemImage: "arrow.triangle.branch")
            Spacer(minLength: Spacing.s)
            if let agent {
                agent.logo.resizable().scaledToFit()
                    .frame(width: IconSize.m, height: IconSize.m)
                    .accessibilityLabel(agent.title)
            }
        }
        .font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
    }
}
