import SwiftUI

struct SidebarFolderRow: View {
    @Bindable var store: WorkspaceStore
    let group: SidebarFilterResult.Group
    let query: String
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    private var folder: ProjectFolder { group.folder }

    var body: some View {
        DisclosureGroup(isExpanded: expanded) {
            ForEach(group.subgroups) { subgroup in
                SidebarFolderRow(store: store, group: subgroup, query: query, sheet: $sheet, removal: $removal)
            }
            ForEach(group.projects) { project in
                SidebarProjectRow(store: store, project: project, query: query, showAll: group.showsAll, sheet: $sheet, removal: $removal)
            }
            if group.isEmpty {
                Button("Ajouter un projet…") { store.chooseProjects(in: folder.id) }
                    .font(Typography.m).foregroundStyle(Palette.textSecondary)
                    .buttonStyle(.plain).padding(.vertical, Spacing.xs)
            }
        } label: {
            HStack {
                Label {
                    Text(folder.name)
                } icon: {
                    Image(systemName: folder.appearance.displaySymbol.systemName)
                        .foregroundStyle(folder.appearance.color)
                }
                .fontWeight(.medium).lineLimit(1)
                Spacer(minLength: Spacing.xs)
                Text("\(group.total)")
                    .font(Typography.caption).monospacedDigit().foregroundStyle(Palette.textSecondary)
            }
            .help(folder.name)
            .draggable(folder.id.uuidString)
            .contextMenu {
                Button("Ajouter des projets…", systemImage: "plus") { store.chooseProjects(in: folder.id) }
                Button("Nouveau sous-dossier…", systemImage: "folder.badge.plus") { sheet = .folder(parentID: folder.id) }
                Button("Renommer et personnaliser…", systemImage: "paintpalette") { sheet = .rename(folder.id, folder.name) }
                Menu("Déplacer vers", systemImage: "folder") {
                    Button("Racine") { store.moveFolder(folder.id, to: nil) }
                        .disabled(!store.canMoveFolder(folder.id, to: nil))
                    ForEach(store.folders.destinations(excluding: folder.id)) { destination in
                        Button(destination.title) { store.moveFolder(folder.id, to: destination.id) }
                            .disabled(!store.canMoveFolder(folder.id, to: destination.id))
                    }
                }
                Divider()
                Button("Dissoudre le dossier", systemImage: "folder.badge.minus") { store.removeFolder(folder.id) }
            }
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let id = UUID(uuidString: value) else { return false }
            return store.drop(id, into: folder.id)
        }
    }

    private var expanded: Binding<Bool> {
        query.isEmpty ? $store[expanded: folder.id] : .constant(true)
    }
}
