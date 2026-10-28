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
                Text("Projets").font(.headline)
                Spacer()
                Menu {
                    Button("Ajouter un projet…", systemImage: "folder.badge.plus") { store.chooseProjects() }
                        .keyboardShortcut("o")
                    Button("Importer un dossier…", systemImage: "square.and.arrow.down") { store.chooseFolder() }
                    Divider()
                    Button("Nouveau dossier virtuel…", systemImage: "folder.badge.plus") { sheet = .folder(parentID: nil) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Ajouter des projets ou un dossier virtuel")
                .accessibilityLabel("Ajouter des projets ou un dossier virtuel")
                .disabled(store.isReadOnly || store.isImporting)
            }
            .padding(.horizontal, 14).padding(.top, 8)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les projets et terminaux", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filtrer les projets et terminaux")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Effacer le filtre")
                }
            }
            .font(.system(size: 12))
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)

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
            .overlay {
                if store.projects.isEmpty && store.folders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 26, weight: .light))
                        Text("Tes projets, au même endroit").font(.system(size: 12, weight: .medium))
                        Text("Ajoute un projet pour commencer.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Ajouter un projet…") { store.chooseProjects() }.controlSize(.small).padding(.top, 4)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                } else if !search.isEmpty && filtered.groups.isEmpty && filtered.ungrouped.isEmpty {
                    Text("Aucun résultat").font(.callout).foregroundStyle(.secondary)
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
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text(store.isImporting ? "Recherche des dépôts…" : "\(store.terminalCount) terminaux")
                Spacer()
                if store.isImporting { ProgressView().controlSize(.mini) }
                else { Text("\(store.sessions.runningCount) ouverts") }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
}

struct WorkspaceWelcomeView: View {
    let store: WorkspaceStore
    @Binding var sheet: WorkspaceSheet?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary)
            Text("Un espace pour tes projets").font(.system(size: 22, weight: .semibold))
            Text("Regroupe tes projets, ouvre des terminaux\net travaille sur plusieurs branches à la fois.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing: 12) {
                Button("Ajouter un projet…") { store.chooseProjects() }.buttonStyle(.borderedProminent)
                Button("Importer un dossier…") { store.chooseFolder() }
            }.padding(.top, 6)
            Button("Créer un dossier virtuel") { sheet = .folder(parentID: nil) }.buttonStyle(.link).font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("AgentUI")
    }

}
