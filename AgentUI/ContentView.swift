import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("inspectorVisible") private var inspectorVisible = true

    @Environment(UsageStore.self) private var usage

    @State private var sheet: WorkspaceSheet?
    @State private var removal: Removal?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Bindable var store: WorkspaceStore

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(sheet: $sheet, removal: $removal, store: store)
                .navigationSplitViewColumnWidth(min: Dimension.Sidebar.minWidth, ideal: Dimension.Sidebar.idealWidth, max: Dimension.Sidebar.maxWidth)
                .navigationTitle("AgentUI")
        } detail: {
            if let context = store.selectedContext {
                TerminalDetail(store: store, context: context)
                    .id(context.terminal.id)
            } else {
                WorkspaceWelcomeView(sheet: $sheet, store: store)
            }
        }
        .inspector(isPresented: $inspectorVisible) {
            WorkspaceInspector(store: store)
                .inspectorColumnWidth(min: Dimension.Inspector.minWidth, ideal: Dimension.Inspector.idealWidth, max: Dimension.Inspector.maxWidth)
        }
        .disabled(store.isReadOnly)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isReadOnly {
                HStack {
                    Label("Organisation illisible. Les modifications sont désactivées pour préserver tes données.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Réessayer") { store.retryLoading() }
                }
                .font(Typography.body).padding(Spacing.l).background(Palette.bar)
            } else if let error = store.persistenceError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(2).help(error)
                    Spacer()
                    Button("Réessayer la sauvegarde") { Task { try? await store.flushPersistence() } }
                }
                .font(Typography.body).padding(Spacing.l).background(Palette.bar)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: Dimension.Window.minWidth, minHeight: Dimension.Window.minHeight)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help(inspectorVisible ? "Masquer le panneau de droite" : "Afficher le panneau de droite")
                    .accessibilityLabel("Afficher ou masquer le panneau de droite")
            }

        }
        .task {
            while !Task.isCancelled {
                await store.sessions.refreshRepositories(worktreePaths: store.projects.flatMap(\.worktrees).map(\.path))
                do { try await Task.sleep(for: .seconds(2)) }
                catch { break }
            }
        }
        .task { await usage.monitor() }
        .sheet(item: $sheet) { item in
            WorkspaceEditor(store: store, sheet: item)
        }
        .alert("Impossible de terminer l’opération", isPresented: $store.errorMessage.isPresent) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog(removal?.title ?? "Retirer", isPresented: $removal.isPresent, titleVisibility: .visible) {
            Button(removal?.confirmation ?? "Retirer", role: .destructive) {
                if let removal {
                    switch removal {
                    case .project(let id): store.removeProject(id)
                    case .terminal(let id): store.closeTerminal(id)
                    case .worktree(let projectID, let worktreeID, _): deleteWorktree(projectID: projectID, worktreeID: worktreeID)
                    }
                }
                removal = nil
            }
        } message: { Text(removal?.message ?? "") }
    }

    private func deleteWorktree(projectID: UUID, worktreeID: UUID) {
        Task {
            do { try await store.deleteWorktree(projectID: projectID, worktreeID: worktreeID) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}

enum Removal {
    case project(UUID), terminal(UUID), worktree(projectID: UUID, worktreeID: UUID, name: String)
    var title: String {
        switch self {
        case .project: "Retirer ce projet de la barre latérale ?"
        case .terminal: "Fermer ce terminal ?"
        case .worktree(_, _, let name): "Supprimer définitivement le worktree « \(name) » ?"
        }
    }
    var confirmation: String {
        switch self {
        case .project: "Retirer"
        case .terminal: "Fermer"
        case .worktree: "Supprimer pour toujours"
        }
    }
    var message: String {
        switch self {
        case .project, .terminal:
            "Les processus des terminaux concernés seront arrêtés. Les fichiers et les worktrees sur disque seront conservés."
        case .worktree:
            "Ses terminaux seront fermés et son dossier sera effacé du disque, y compris les modifications non commitées. Cette action est irréversible. La branche et ses commits restent dans le dépôt."
        }
    }
}
