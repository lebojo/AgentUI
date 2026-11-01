import SwiftUI

struct MobileSidebar: View {
    @State private var search = ""
    @State private var filtered = SidebarFilterResult()

    @Bindable var store: MobileWorkspaceStore

    let showSettings: () -> Void

    private var selection: Binding<MobileSidebarSelection?> {
        Binding(get: { store.selection.map(MobileSidebarSelection.terminal) }, set: { value in
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
}

private struct MobileFolderRow: View {
    let group: SidebarFilterResult.Group

    var body: some View {
        DisclosureGroup {
            ForEach(group.subgroups) { subgroup in MobileFolderRow(group: subgroup) }
            ForEach(group.projects) { project in MobileProjectRow(project: project) }
        } label: {
            Label(group.folder.name, systemImage: group.folder.appearance.displaySymbol.systemName)
        }
        .selectionDisabled()
    }
}

private struct MobileProjectRow: View {
    @State private var expanded = true

    let project: Project

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(project.worktrees) { worktree in
                MobileWorktreeRow(worktree: worktree)
            }
        } label: {
            Label(project.name, systemImage: project.appearance.displaySymbol.systemName)
        }
        .selectionDisabled()
    }
}

private struct MobileWorktreeRow: View {
    @Environment(MobileWorkspaceStore.self) private var store

    @State private var expanded = true

    let worktree: Worktree

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(worktree.terminals) { terminal in
                NavigationLink(value: MobileSidebarSelection.terminal(terminal.id)) {
                    Label { Text(terminal.name) } icon: { TerminalIcon(agent: store.terminalAgents[terminal.id]) }
                }
                    .selectionDisabled(false)
            }
        } label: {
            Label(worktree.name, systemImage: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
        }
        .selectionDisabled()
    }
}

private enum MobileSidebarSelection: Hashable {
    case terminal(UUID)

    var terminalID: UUID {
        switch self { case .terminal(let id): id }
    }
}
