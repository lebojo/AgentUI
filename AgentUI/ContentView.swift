import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("inspectorVisible") private var inspectorVisible = true

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
        .modifier(WorkspaceMonitors(store: store))
        .sheet(item: $sheet) { item in
            WorkspaceEditor(store: store, sheet: item)
        }
        .alert("Impossible de terminer l’opération", isPresented: $store.errorMessage.isPresent) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .background { RemovalConfirmation(removal: $removal, store: store) }
    }
}
