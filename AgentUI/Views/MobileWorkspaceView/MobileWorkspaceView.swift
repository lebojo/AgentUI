import SwiftUI

struct MobileWorkspaceView: View {
    @AppStorage("mobileSessionDisplayMode") private var mode: SessionDisplayMode = .chat

    @Environment(\.scenePhase) private var scenePhase

    @State private var store = MobileWorkspaceStore()
    @State private var inspectorVisible = false
    @State private var settingsVisible = false

    private var isInBackground: Bool { scenePhase == .background }
    private var watchKey: String {
        "\(store.connectionID)|\(store.selection?.uuidString ?? "")|\(mode.rawValue)|\(store.wantsConnection)|\(isInBackground)"
    }

    var body: some View {
        WorkspaceSplitView(inspectorVisible: $inspectorVisible) {
            MobileSidebar(store: store, showSettings: { settingsVisible = true })
        } detail: {
            MobileSessionDetail(mode: mode, store: store, showSettings: { settingsVisible = true })
        } inspector: {
            if let context = store.context {
                WorkspaceInspector(context: context,
                                   source: MobileInspectorSource(host: store.host, terminal: context.terminal.id, store: store))
                    .id(context.terminal.id)
            } else {
                ContentUnavailableView("Aucun terminal sélectionné", systemImage: "sidebar.right")
            }
        }
        .sheet(isPresented: $settingsVisible) { MobileSettingsView(store: store) }
        .task(id: watchKey) {
            guard !isInBackground else { store.suspend(); return }
            await store.watch(prefersChat: mode == .chat)
        }
        .alert("Opération impossible", isPresented: $store.error.isPresent) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
