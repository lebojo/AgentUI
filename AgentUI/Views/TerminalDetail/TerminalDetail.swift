import AppKit
import SwiftUI

struct TerminalDetail: View {
    let store: WorkspaceStore
    let context: TerminalContext

    private var layout: TerminalLayout { store.layout(for: context.terminal.id) }

    var body: some View {
        VStack(spacing: 0) {
            TerminalHeader(store: store, context: context)

            Divider()

            TerminalLayoutView(store: store, layout: layout, focusedID: context.terminal.id, isSplit: layout.isSplit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            TerminalFooter(session: store.sessions.session(context.terminal.id), path: context.worktree.path)
        }
        .background(Palette.surface)
        .navigationTitle(context.terminal.name)
    }
}

private struct TerminalHeader: View {
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
                .buttonStyle(.borderless).help("Diviser à droite (⌘D)")
                .accessibilityLabel("Diviser le terminal à droite")
                .keyboardShortcut("d")
            Button { split(.vertical) } label: { Image(systemName: "rectangle.split.1x2") }
                .buttonStyle(.borderless).help("Diviser en bas (⇧⌘D)")
                .accessibilityLabel("Diviser le terminal en bas")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(action: addTerminal) { Label("Terminal", systemImage: "plus") }
                .buttonStyle(.borderless).help("Nouveau terminal dans ce worktree")
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

private struct TerminalFooter: View {
    let session: TerminalSession?
    let path: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "folder").foregroundStyle(Palette.textSecondary)
            Text((session?.currentDirectory ?? path).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: Spacing.l)
            Text("⌘T  Nouveau terminal   ⌘D  Diviser").foregroundStyle(Palette.textSecondary)
        }
        .font(Typography.s).foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.xl).frame(height: Dimension.Detail.footerHeight)
    }
}
