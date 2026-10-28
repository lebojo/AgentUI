import SwiftUI
import AppKit

struct TerminalDetail: View {
    let store: WorkspaceStore
    let context: TerminalContext
    @State private var session: TerminalSession?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
                Text(context.project.name).fontWeight(.medium)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                Text(context.worktree.name).foregroundStyle(.secondary)
                if let branch = store.sessions.branch(for: context.terminal.id, initialPath: context.worktree.path) {
                    BranchBadge(branch: branch).frame(maxWidth: 180)
                }
                Spacer()
                Button {
                    do { _ = try store.addTerminal(projectID: context.project.id, worktreeID: context.worktree.id) }
                    catch { store.errorMessage = error.localizedDescription }
                } label: { Label("Terminal", systemImage: "plus") }
                .buttonStyle(.borderless).help("Nouveau terminal dans ce worktree")
                .keyboardShortcut("t")
            }
            .font(.system(size: 12)).lineLimit(1).padding(.horizontal, 18).frame(height: 40)
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
                    .font(.callout).padding(12).background(.bar)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text((session?.currentDirectory ?? context.worktree.path).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 12)
                Text("⌘T  Nouveau terminal").foregroundStyle(.secondary)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 29)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(context.terminal.name)
        .task { session = store.sessions.start(context) }
    }
}
