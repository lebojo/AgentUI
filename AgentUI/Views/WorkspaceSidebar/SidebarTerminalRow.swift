import SwiftUI
import AppKit

struct SidebarTerminalRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let terminal: TerminalRecord
    let worktree: Worktree

    private var session: TerminalSession? { store.sessions.session(terminal.id) }
    private var branch: GitBranch? { store.sessions.branch(for: terminal.id, initialPath: worktree.path) }
    private var subagents: [Subagent] {
        (session?.subagents ?? []).filter { $0.isVisible || $0.id == store.selection }
    }

    private var row: some View {
        HStack(spacing: Spacing.s) {
            TerminalIcon(agent: session?.agentKind)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(terminal.name).lineLimit(1)
                    .foregroundStyle(session == nil ? Palette.textSecondary : Palette.textPrimary)
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: branch?.isDetached == true ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.triangle.branch")
                        .font(Typography.xxs)
                    Text(branch?.name ?? worktree.displayName).lineLimit(1).truncationMode(.middle)
                }
                .font(Typography.s).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xs)
            if let status = session?.agentStatus {
                AgentStatusBadge(title: status.title, color: status.color)
            } else if let session {
                Image(systemName: session.hasExited ? "circle" : "circle.fill")
                    .font(Typography.statusDot).foregroundStyle(session.hasExited ? Palette.textSecondary : Palette.success)
                    .accessibilityLabel(session.hasExited ? "Session ended" : "Terminal open")
            } else {
                Image(systemName: "moon").font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel("Idle terminal")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .tag(terminal.id)
        .help(session == nil ? String(localized: "\(terminal.name) — idle, click to open it") : terminal.name)
        .contextMenu {
            Button("Rename…", systemImage: "pencil") { sheet = .rename(terminal.id, terminal.name) }
            if terminal.hasCustomName {
                Button("Use Conversation Name", systemImage: "bubble.left") { store.useAutomaticName(terminal.id) }
            }
            Divider()
            RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .menu)
        }
        .swipeActions(edge: .trailing) {
            RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .swipe)
        }
    }

    var body: some View {
        if subagents.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: $store[expanded: terminal.id]) {
                ForEach(subagents) { subagent in
                    SidebarSubagentRow(subagent: subagent)
                }
            } label: {
                row
            }
        }
    }
}
