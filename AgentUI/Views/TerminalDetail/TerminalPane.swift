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
    private var startableTerminal: UUID? { store.startableContext(for: context.terminal.id)?.terminal.id }

    var body: some View {
        VStack(spacing: 0) {
            if isSplit {
                TerminalPaneHeader(title: context.terminal.name,
                                   branch: store.sessions.branch(for: context.terminal.id, initialPath: context.worktree.path),
                                   isFocused: isFocused) { store.closeTerminal(context.terminal.id) }
                    .onTapGesture { select() }
                    .terminalDragSource(context.terminal.id)
                Divider()
            }
            if let session {
                if displayMode == .chat, session.agent != nil {
                    LocalSessionChat(session: session)
                        .simultaneousGesture(TapGesture().onEnded { select() })
                        .overlay(alignment: .topTrailing) { RemoteGridBadge(session: session) }
                } else {
                    NativeTerminalView(session: session, appearance: settings.terminal, isFocused: isFocused) { select() }
                        .id(ObjectIdentifier(session))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { RemoteGridBadge(session: session) }
                    if displayMode == .chat, !session.hasExited, !installedAgents.agents.isEmpty {
                        AgentShortcutBar(agents: installedAgents.agents) { agent in launch(agent, in: session) }
                            .disabled(session.isLaunchingAgent)
                    }
                }
                SessionEndedBar(session: session) {
                    store.sessions.close(context.terminal.id)
                    store.startSession(for: context.terminal.id)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: startableTerminal) { store.startSession(for: context.terminal.id) }
    }

    private func select() {
        if store.selection != context.terminal.id { store.selection = context.terminal.id }
    }

    private func launch(_ agent: ConversationAgent, in session: TerminalSession) {
        select()
        Task {
            do { try await session.launch(agent, skippingPermissions: settings.agentLaunch.skipsPermissions, from: .local) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}
