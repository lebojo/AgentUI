import SwiftUI

struct WorkspaceInspector: View {
    @AppStorage("inspectorTab") private var tab: InspectorTab = .files

    let context: TerminalContext?
    let source: any InspectorSource

    var body: some View {
        Group {
            if let context {
                InspectorContents(context: context, tab: tab, source: source)
                    .id(context.worktree.id)
            } else {
                ContentUnavailableView("No Terminal Selected", systemImage: tab.symbol,
                                       description: Text("Open a terminal to explore its project."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            Picker("Right Panel View", selection: $tab) {
                ForEach(InspectorTab.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(.iconOnly)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.s)
        }
    }
}
