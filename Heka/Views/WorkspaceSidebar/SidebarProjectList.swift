import SwiftUI

struct SidebarProjectList: View {
    @Environment(WorkspaceStore.self) private var store

    let result: SidebarFilterResult
    let query: String

    private var orphans: [DiscoveredWorktree] {
        store.orphanWorktrees.filter { query.isEmpty || $0.folderName.localizedStandardContains(query) || ($0.branch?.localizedStandardContains(query) ?? false) }
    }

    var body: some View {
        List(selection: Bindable(store).selection) {
            SidebarWorkInProgressSection(query: query)
            Section {
                ForEach(result.groups) { group in
                    SidebarFolderRow(group: group, query: query)
                }
                .onMove(perform: store.isReadOnly ? nil : { store.reorderFolders(result.groups.map(\.id), from: $0, to: $1) })
                ForEach(result.ungrouped) { project in
                    SidebarProjectRow(project: project, query: query, showAll: false)
                }
                .onMove(perform: store.isReadOnly ? nil : { store.reorderProjects(result.ungrouped.map(\.id), from: $0, to: $1) })
            }
            if !orphans.isEmpty {
                Section("Orphans") {
                    ForEach(orphans) { worktree in
                        SidebarOrphanRow(worktree: worktree)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { UsageBar() }
        .overlay {
            if store.projects.isEmpty && store.folders.isEmpty && store.orphanWorktrees.isEmpty {
                VStack(spacing: Spacing.m) {
                    Image(systemName: "folder.badge.plus").font(Typography.emptyStateSymbol)
                    Text("All your projects in one place").font(Typography.m.weight(.medium))
                    Text("Add a project to get started.").font(Typography.s).foregroundStyle(Palette.textSecondary)
                    Button("Add Project…") { store.chooseProjects() }.controlSize(.small).padding(.top, Spacing.xs)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding()
            } else if !query.isEmpty && result.groups.isEmpty && result.ungrouped.isEmpty && orphans.isEmpty {
                Text("No Results").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
