import AppKit
import SwiftUI

struct TerminalDetail: View {
    @State private var session: TerminalSession?

    let store: WorkspaceStore
    let context: TerminalContext

    var body: some View {
        VStack(spacing: 0) {
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
                Button {
                    do { _ = try store.addTerminal(projectID: context.project.id, worktreeID: context.worktree.id) }
                    catch { store.errorMessage = error.localizedDescription }
                } label: { Label("Terminal", systemImage: "plus") }
                    .buttonStyle(.borderless).help("Nouveau terminal dans ce worktree")
                    .keyboardShortcut("t")
            }
            .font(Typography.m).lineLimit(1).padding(.horizontal, Spacing.xl).frame(height: Dimension.Detail.headerHeight)

            Divider()

            if let session {
                NativeTerminalView(session: session)
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if session.hasExited {
                    HStack {
                        Label(session.exitCode.map { "Session terminée (\($0))" } ?? "Session terminée", systemImage: "stop.circle")
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
            Divider()
            HStack(spacing: Spacing.m) {
                Image(systemName: "folder").foregroundStyle(Palette.textSecondary)
                Text((session?.currentDirectory ?? context.worktree.path).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: Spacing.l)
                Text("⌘T  Nouveau terminal").foregroundStyle(Palette.textSecondary)
            }
            .font(Typography.s).foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xl).frame(height: Dimension.Detail.footerHeight)
        }
        .background(Palette.surface)
        .navigationTitle(context.terminal.name)
        .task { session = store.sessions.start(context) }
    }
}
