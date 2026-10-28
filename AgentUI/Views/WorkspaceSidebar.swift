import SwiftUI
import AppKit

struct WorkspaceSidebar: View {
    @Bindable var store: WorkspaceStore
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?
    @State private var search = ""
    @State private var filtered = SidebarFilterResult()
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

            List(selection: $store.selection) {
                Section {
                    ForEach(filtered.groups) { group in
                        SidebarFolderRow(store: store, group: group, query: search, sheet: $sheet, removal: $removal)
                    }
                    ForEach(filtered.ungrouped) { project in
                        SidebarProjectRow(store: store, project: project, query: search, showAll: false, sheet: $sheet, removal: $removal)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) { UsageBar() }
            .overlay {
                if store.projects.isEmpty && store.folders.isEmpty {
                    VStack(spacing: Spacing.m) {
                        Image(systemName: "folder.badge.plus").font(Typography.emptyStateSymbol)
                        Text("Tes projets, au même endroit").font(Typography.m.weight(.medium))
                        Text("Ajoute un projet pour commencer.").font(Typography.s).foregroundStyle(Palette.textSecondary)
                        Button("Ajouter un projet…") { store.chooseProjects() }.controlSize(.small).padding(.top, Spacing.xs)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding()
                } else if !search.isEmpty && filtered.groups.isEmpty && filtered.ungrouped.isEmpty {
                    Text("Aucun résultat").font(Typography.body).foregroundStyle(Palette.textSecondary)
                }
            }
            SidebarFooter(store: store)

        }
        .onChange(of: SidebarFilterInput(folders: store.folders, projects: store.projects, query: search), initial: true) { _, input in
            filtered = input.filtered()
        }
    }
}

private struct SidebarFooter: View {
    let store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.s) {
                Image(systemName: "terminal")
                Text(store.isImporting ? "Recherche des dépôts…" : "\(store.terminalCount) terminaux")
                Spacer()
                if store.isImporting { ProgressView().controlSize(.mini) }
                else { Text("\(store.sessions.runningCount) ouverts") }
            }
            .font(Typography.s).foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }
}

struct WorkspaceWelcomeView: View {
    let store: WorkspaceStore
    @Binding var sheet: WorkspaceSheet?
    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "terminal").font(Typography.heroSymbol).foregroundStyle(Palette.textSecondary)
            Text("Un espace pour tes projets").font(Typography.display)
            Text("Regroupe tes projets, ouvre des terminaux\net travaille sur plusieurs branches à la fois.")
                .font(Typography.l).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).lineSpacing(Spacing.xs)
            HStack(spacing: Spacing.l) {
                Button("Ajouter un projet…") { store.chooseProjects() }.buttonStyle(.borderedProminent)
                Button("Importer un dossier…") { store.chooseFolder() }
            }.padding(.top, Spacing.s)
            Button("Créer un dossier virtuel") { sheet = .folder(parentID: nil) }.buttonStyle(.link).font(Typography.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .navigationTitle("AgentUI")
    }

}
