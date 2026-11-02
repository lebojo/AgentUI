import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("inspectorVisible") private var inspectorVisible = true

    @Environment(AppVisibility.self) private var visibility

    @State private var sheet: WorkspaceSheet?
    @State private var removal: Removal?

    @Bindable var store: WorkspaceStore

    var body: some View {
        WorkspaceSplitView(inspectorVisible: $inspectorVisible) {
            WorkspaceSidebar(sheet: $sheet, removal: $removal, store: store)
                .disabled(store.isReadOnly)
        } detail: {
            Group {
                if let context = store.selectedContext, let selected = store.selectedSubagent {
                    SubagentDetail(store: store, context: context, subagent: selected.subagent)
                } else if let context = store.selectedContext {
                    TerminalDetail(store: store, context: context)
                } else {
                    WorkspaceWelcomeView(sheet: $sheet, store: store)
                }
            }
            .disabled(store.isReadOnly)
        } inspector: {
            WorkspaceInspector(context: store.selectedContext, source: LocalInspectorSource(store: store))
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
        .sheet(item: $sheet) { item in
            WorkspaceEditor(store: store, sheet: item)
        }
        .sheet(item: $store.pendingImport, onDismiss: store.showNextImport) { plan in
            RepositoryImportSheet(store: store, plan: plan)
        }
        .alert("Couldn’t Complete the Operation", isPresented: $store.errorMessage.isPresent) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .background { RemovalConfirmation(removal: $removal, store: store) }
    }
}
