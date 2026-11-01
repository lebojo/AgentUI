import SwiftUI

struct TerminalPane: View {
    @AppStorage("sessionDisplayMode") private var displayMode: SessionDisplayMode = .terminal

    @Environment(SettingsStore.self) private var settings
    @Environment(InstalledAgents.self) private var installedAgents

    let store: WorkspaceStore
    let context: TerminalContext
    let isFocused: Bool
    let isSplit: Bool

    private var session: TerminalSession? { store.sessions.session(context.terminal.id) }

    var body: some View {
        VStack(spacing: 0) {
            if isSplit {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "terminal").foregroundStyle(isFocused ? Palette.accent : Palette.textSecondary)
                    Text(context.terminal.name).lineLimit(1)
                        .foregroundStyle(isFocused ? Palette.textPrimary : Palette.textSecondary)
                    if let branch = store.sessions.branch(for: context.terminal.id, initialPath: context.worktree.path) {
                        BranchBadge(branch: branch).frame(maxWidth: Dimension.Badge.sidebarMaxWidth)
                    }
                    Spacer(minLength: Spacing.xs)
                    Button { store.closeTerminal(context.terminal.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Fermer ce panneau")
                        .accessibilityLabel("Fermer le terminal \(context.terminal.name)")
                }
                .font(Typography.s).padding(.horizontal, Spacing.l).frame(height: Dimension.Detail.paneTitleHeight)
                .background(isFocused ? Palette.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { store.selection = context.terminal.id }
                Divider()
            }
            if let session {
                if displayMode == .chat, session.agent != nil {
                    LocalSessionChat(session: session)
                        .simultaneousGesture(TapGesture().onEnded { store.selection = context.terminal.id })
                } else {
                    NativeTerminalView(session: session, appearance: settings.terminal, isFocused: isFocused) {
                        if store.selection != context.terminal.id { store.selection = context.terminal.id }
                    }
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if displayMode == .chat, !session.hasExited, !installedAgents.agents.isEmpty {
                        AgentShortcutBar(agents: installedAgents.agents) { agent in launch(agent, in: session) }
                            .disabled(session.isLaunchingAgent)
                    }
                }
                if session.hasExited {
                    HStack {
                        SessionExitLabel(code: session.exitCode)
                        Spacer()
                        Button("Rouvrir le terminal") {
                            store.sessions.close(context.terminal.id)
                            store.sessions.start(context)
                        }
                    }
                    .font(Typography.body).padding(Spacing.l).background(Palette.bar)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: context.terminal.id) { store.sessions.start(context) }
    }

    private func launch(_ agent: ConversationAgent, in session: TerminalSession) {
        store.selection = context.terminal.id
        Task {
            do { try await session.launch(agent, skippingPermissions: settings.agentLaunch.skipsPermissions) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}
