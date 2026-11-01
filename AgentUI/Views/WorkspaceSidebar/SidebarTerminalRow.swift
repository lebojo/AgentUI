import SwiftUI
import AppKit

struct SidebarTerminalRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let store: WorkspaceStore
    let terminal: TerminalRecord
    let worktree: Worktree

    private var session: TerminalSession? { store.sessions.session(terminal.id) }
    private var branch: GitBranch? { store.sessions.branch(for: terminal.id, initialPath: worktree.path) }

    var body: some View {
        HStack(spacing: Spacing.s) {
            TerminalIcon(agent: session?.agentKind)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(terminal.name).lineLimit(1)
                    .foregroundStyle(session == nil ? Palette.textSecondary : Palette.textPrimary)
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: branch?.isDetached == true ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.triangle.branch")
                        .font(Typography.xxs)
                    Text(branch?.name ?? worktree.name).lineLimit(1).truncationMode(.middle)
                }
                .font(Typography.s).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xs)
            if let status = session?.agentStatus {
                AgentStatusBadge(status: status)
            } else if let session {
                Image(systemName: session.hasExited ? "circle" : "circle.fill")
                    .font(Typography.statusDot).foregroundStyle(session.hasExited ? Palette.textSecondary : Palette.success)
                    .accessibilityLabel(session.hasExited ? "Session terminée" : "Terminal ouvert")
            } else {
                Image(systemName: "moon").font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel("Terminal en veille")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .tag(terminal.id)
        .help(session == nil ? "\(terminal.name) — en veille, cliquer pour l’ouvrir" : terminal.name)
        .contextMenu {
            Button("Renommer…", systemImage: "pencil") { sheet = .rename(terminal.id, terminal.name) }
            if terminal.hasCustomName {
                Button("Utiliser le nom de la conversation", systemImage: "bubble.left") { store.useAutomaticName(terminal.id) }
            }
            Divider()
            RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .menu)
        }
        .swipeActions(edge: .trailing) {
            RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .swipe)
        }
    }
}
