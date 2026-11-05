import SwiftUI

struct SidebarTerminalLabel: View {
    let name: String
    let session: TerminalSession?

    var body: some View {
        HStack(spacing: Spacing.s) {
            TerminalIcon(agent: session?.agentKind)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name).lineLimit(1)
                    .foregroundStyle(session == nil ? Palette.textSecondary : Palette.textPrimary)
                if let divergentBranch = session?.divergentBranch {
                    SidebarBranchName(branch: divergentBranch, color: Palette.danger)
                        .help("This terminal is on a different branch from its worktree")
                }
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
        .help(session == nil ? String(localized: "\(name) — idle, click to open it") : name)
    }
}
