import SwiftUI

struct WorkspaceSplitView<Sidebar: View, Detail: View, Inspector: View>: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Binding var inspectorVisible: Bool

    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let inspector: () -> Inspector

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar()
                .navigationTitle("AgentUI")
                .navigationSplitViewColumnWidth(min: Dimension.Sidebar.minWidth, ideal: Dimension.Sidebar.idealWidth,
                                                max: Dimension.Sidebar.maxWidth)
        } detail: {
            detail()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Right Panel", systemImage: "sidebar.right") { inspectorVisible.toggle() }
                            .labelStyle(.iconOnly)
                            .help(inspectorVisible ? "Hide Right Panel" : "Show Right Panel")
                            .accessibilityLabel("Show or hide the right panel")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $inspectorVisible) {
            inspector()
                .inspectorColumnWidth(min: Dimension.Inspector.minWidth, ideal: Dimension.Inspector.idealWidth,
                                      max: Dimension.Inspector.maxWidth)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
