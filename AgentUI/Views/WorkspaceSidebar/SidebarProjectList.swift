import SwiftUI
import AppKit

struct SidebarProjectList: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let result: SidebarFilterResult
    let query: String

    var body: some View {
        List(selection: $store.selection) {
            Section {
                ForEach(result.groups) { group in
                    SidebarFolderRow(sheet: $sheet, removal: $removal, store: store, group: group, query: query)
                }
                ForEach(result.ungrouped) { project in
                    SidebarProjectRow(sheet: $sheet, removal: $removal, store: store, project: project, query: query, showAll: false)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { UsageBar() }
        .overlay {
            if store.projects.isEmpty && store.folders.isEmpty {
                VStack(spacing: Spacing.m) {
                    Image(systemName: "folder.badge.plus").font(Typography.emptyStateSymbol)
                    Text("All your projects in one place").font(Typography.m.weight(.medium))
                    Text("Add a project to get started.").font(Typography.s).foregroundStyle(Palette.textSecondary)
                    Button("Add Project…") { store.chooseProjects() }.controlSize(.small).padding(.top, Spacing.xs)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding()
            } else if !query.isEmpty && result.groups.isEmpty && result.ungrouped.isEmpty {
                Text("No Results").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
