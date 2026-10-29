import SwiftUI

struct TerminalPane: View {
    @Environment(SettingsStore.self) private var settings

    @State private var session: TerminalSession?

    let store: WorkspaceStore
    let context: TerminalContext
    let isFocused: Bool
    let isSplit: Bool

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
                NativeTerminalView(session: session, appearance: settings.terminal, isFocused: isFocused) {
                    if store.selection != context.terminal.id { store.selection = context.terminal.id }
                }
                .id(ObjectIdentifier(session))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if session.hasExited {
                    HStack {
                        Label(exitDescription(session.exitCode), systemImage: "stop.circle")
                        Spacer()
                        Button("Rouvrir le terminal") {
                            store.sessions.close(context.terminal.id)
                            self.session = store.sessions.start(context)
                        }
                    }
                    .font(Typography.body).padding(Spacing.l).background(Palette.bar)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { session = store.sessions.start(context) }
    }

    private func exitDescription(_ code: Int32?) -> String {
        switch code {
        case nil: "Session terminée"
        case 127: "Commande introuvable (127) : vérifie qu’elle est installée et dans le PATH de ton shell"
        case let code?: "Session terminée (\(code))"
        }
    }
}
