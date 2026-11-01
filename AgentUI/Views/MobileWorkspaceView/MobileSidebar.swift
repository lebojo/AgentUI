import SwiftUI

struct MobileSidebar: View {
    @State private var search = ""
    @State private var filtered = SidebarFilterResult()

    @Bindable var store: MobileWorkspaceStore

    let showSettings: () -> Void

    private var selection: Binding<Selection?> {
        Binding(get: { store.selection.map(Selection.terminal) }, set: { value in
            store.selection = value?.terminalID
        })
    }

    var body: some View {
        List(selection: selection) {
            Section("Projets") {
                ForEach(filtered.groups) { group in MobileFolderRow(group: group) }
                ForEach(filtered.ungrouped) { project in MobileProjectRow(project: project) }
            }
        }
        .environment(store)
        .listStyle(.sidebar)
        .searchable(text: $search, prompt: "Filtrer les projets et terminaux")
        .onChange(of: SidebarFilterInput(folders: store.workspace.folders, projects: store.workspace.projects, query: search), initial: true) { _, input in
            filtered = input.filtered()
        }
        .overlay {
            if store.workspace.projects.isEmpty {
                ContentUnavailableView {
                    Label(store.isConnected ? "Aucun projet" : "Ton Mac, à portée de main", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text(store.isConnected ? "Ajoute un projet dans AgentUI sur le Mac." : "Connecte-toi au réseau local pour continuer une session.")
                } actions: {
                    Button("Se connecter", action: showSettings).buttonStyle(.borderedProminent)
                }
            } else if filtered.groups.isEmpty && filtered.ungrouped.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: store.isConnected ? "network" : "network.slash")
                Text(store.statusText).lineLimit(2)
                Spacer()
                Button("Réglages", systemImage: "gearshape", action: showSettings).labelStyle(.iconOnly)
            }.font(Typography.caption).padding(Spacing.l).background(Palette.bar)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Réglages", systemImage: "gearshape", action: showSettings)
            }
        }
    }

    enum Selection: Hashable {
        case terminal(UUID)

        var terminalID: UUID {
            switch self { case .terminal(let id): id }
        }
    }
}
