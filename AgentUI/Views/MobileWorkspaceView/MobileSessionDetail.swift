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
                        } else {
                            MobileTerminalViewport(session: session)
                                .id(session.identity)
                                .disabled(!store.isConnected || session.hasExited)
                            if mode == .chat, store.isConnected, !session.hasExited, !store.installedAgents.isEmpty {
                                AgentShortcutBar(agents: store.installedAgents) { agent in
                                    Task { await store.launch(agent, in: context) }
                                }
                            }
                        }
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
                        Button("Settings", systemImage: "gearshape", action: showSettings)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Terminal", systemImage: "plus") { Task { await store.newTerminal(in: context) } }
                            .disabled(!store.isConnected)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(store.isConnected ? "Choose a Terminal" : "Pick Up on Your Mac", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text(store.isConnected ? "Find your projects and sessions in the sidebar." : "Connect to the Mac in Settings to find your projects and sessions.")
                } actions: {
                    Button("Connection Settings", action: showSettings).buttonStyle(.borderedProminent)
                }
                .navigationTitle("AgentUI")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
