import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("inspectorVisible") private var inspectorVisible = true

    @Environment(AppVisibility.self) private var visibility
    @Environment(SettingsStore.self) private var settings
    @Environment(FloatingTerminalStore.self) private var floating

    @State private var presentation = WorkspacePresentation()

    @Bindable var store: WorkspaceStore

    let gitActionQueues: GitActionQueues

    var body: some View {
        WorkspaceSplitView(inspectorVisible: $inspectorVisible) {
            WorkspaceSidebar()
                .disabled(store.isReadOnly)
        } detail: {
            Group {
                if let context = store.selectedContext, let selected = store.selectedSubagent {
                    SubagentDetail(store: store, context: context, subagent: selected.subagent)
                } else if let context = store.selectedContext {
                    TerminalDetail(store: store, context: context)
                } else {
                    WorkspaceWelcomeView()
                }
            }
            .disabled(store.isReadOnly)
        } inspector: {
            WorkspaceInspector(context: store.selectedContext, source: LocalInspectorSource(store: store, settings: settings, gitActionQueues: gitActionQueues))
                .disabled(store.isReadOnly)
        }
        .environment(\.workspaceVisible, visibility.isVisible)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isReadOnly {
                HStack {
                    Label("Unreadable organization. Changes are disabled to protect your data.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Retry") { store.retryLoading() }
                }
                .font(Typography.body).padding(Spacing.l).background(Palette.bar)
            } else if let error = store.persistenceError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(2).help(error)
                    Spacer()
                    Button("Retry Saving") { Task { try? await store.flushPersistence() } }
                }
                .font(Typography.body).padding(Spacing.l).background(Palette.bar)
            }
        }
        .frame(minWidth: Dimension.Window.minWidth, minHeight: Dimension.Window.minHeight)
        .modifier(WorkspaceMonitors(store: store))
        .sheet(item: Bindable(presentation).sheet) { item in
            WorkspaceEditor(store: store, sheet: item)
        }
        .sheet(isPresented: Bindable(floating).isPresented) {
            FloatingTerminalView()
        }
        .sheet(item: $store.pendingImport, onDismiss: store.showNextImport) { plan in
            RepositoryImportSheet(store: store, plan: plan)
        }
        .alert("Couldn’t Complete the Operation", isPresented: $store.errorMessage.isPresent) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .background { RemovalConfirmation() }
        .environment(presentation)
    }
}
