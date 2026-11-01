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
                ContentUnavailableView("Aucun terminal sélectionné", systemImage: tab.symbol,
                                       description: Text("Ouvre un terminal pour explorer son projet."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            Picker("Vue du panneau de droite", selection: $tab) {
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
