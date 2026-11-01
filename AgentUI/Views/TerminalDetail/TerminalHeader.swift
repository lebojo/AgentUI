import AppKit
import SwiftUI

struct TerminalHeader: View {
    @Environment(SettingsStore.self) private var settings

    let store: WorkspaceStore
    let context: TerminalContext

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "shippingbox").foregroundStyle(Palette.textSecondary)
            Text(context.project.name).fontWeight(.medium)
            Image(systemName: "chevron.right").font(Typography.xxs).foregroundStyle(Palette.textTertiary)
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
            Text(context.worktree.name).foregroundStyle(Palette.textSecondary)
            if let branch = store.sessions.branch(for: context.terminal.id, initialPath: context.worktree.path) {
                BranchBadge(branch: branch).frame(maxWidth: Dimension.Badge.detailMaxWidth)
            }
            Spacer()
            Button { split(.horizontal) } label: { Image(systemName: "rectangle.split.2x1") }
                .buttonStyle(.borderless).help("Split Right (⌘D)")
                .accessibilityLabel("Split terminal right")
                .keyboardShortcut("d")
            Button { split(.vertical) } label: { Image(systemName: "rectangle.split.1x2") }
                .buttonStyle(.borderless).help("Split Down (⇧⌘D)")
                .accessibilityLabel("Split terminal down")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(action: addTerminal) { Label("Terminal", systemImage: "plus") }
                .buttonStyle(.borderless).help("New terminal in this worktree")
                .keyboardShortcut("t")
        }
        .font(Typography.m).lineLimit(1).padding(.horizontal, Spacing.xl).frame(height: Dimension.Detail.headerHeight)
    }

    private func addTerminal() {
        do {
            _ = try store.addTerminal(projectID: context.project.id, worktreeID: context.worktree.id,
                                      command: settings.agentLaunch.command(on: .newTerminal))
        }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func split(_ axis: SplitAxis) {
        do {
            _ = try store.splitTerminal(context.terminal.id, axis: axis, command: settings.agentLaunch.command(on: .newTerminal))
        }
        catch { store.errorMessage = error.localizedDescription }
    }
}
