import SwiftUI
import AppKit

struct WorkspaceSidebar: View {
    @State private var search = ""
    @State private var filtered = SidebarFilterResult()

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Projets").font(Typography.headline)
                Spacer()
                Menu {
                    Button("Ajouter un projet…", systemImage: "folder.badge.plus") { store.chooseProjects() }
                        .keyboardShortcut("o")
                    Button("Importer un dossier…", systemImage: "square.and.arrow.down") { store.chooseFolder() }
                    Divider()
                    Button("Nouveau dossier virtuel…", systemImage: "folder.badge.plus") { sheet = .folder(parentID: nil) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "plus").frame(width: IconSize.l, height: IconSize.l)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Ajouter des projets ou un dossier virtuel")
                .accessibilityLabel("Ajouter des projets ou un dossier virtuel")
                .disabled(store.isReadOnly || store.isImporting)
            }
            .padding(.horizontal, Spacing.l).padding(.top, Spacing.m)
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
                TextField("Filtrer les projets et terminaux", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filtrer les projets et terminaux")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.textSecondary).accessibilityLabel("Effacer le filtre")
                }
            }
            .font(Typography.m)
            .padding(Spacing.m)
            .background(Palette.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.m))
            .padding(.horizontal, Spacing.l).padding(.top, Spacing.m).padding(.bottom, Spacing.l)

            SidebarProjectList(
                sheet: $sheet,
                removal: $removal,
                store: store,
                result: filtered,
                query: search
            )
            SidebarFooter(store: store)
        }
        .onChange(of: SidebarFilterInput(folders: store.folders, projects: store.projects, query: search), initial: true) { _, input in
            filtered = input.filtered()
        }
    }
}
