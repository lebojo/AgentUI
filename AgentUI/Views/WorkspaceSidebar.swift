import SwiftUI
import AppKit

struct WorkspaceSidebar: View {
    @State private var search = ""

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
                result: SidebarFilterInput(folders: store.folders, projects: store.projects, query: search).filtered(),
                query: search
            )
            SidebarFooter(store: store)

        }
    }
}

private struct SidebarProjectList: View {
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
                    Text("Tes projets, au même endroit").font(Typography.m.weight(.medium))
                    Text("Ajoute un projet pour commencer.").font(Typography.s).foregroundStyle(Palette.textSecondary)
                    Button("Ajouter un projet…") { store.chooseProjects() }.controlSize(.small).padding(.top, Spacing.xs)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding()
            } else if !query.isEmpty && result.groups.isEmpty && result.ungrouped.isEmpty {
                Text("Aucun résultat").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
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
    @Binding var sheet: WorkspaceSheet?

    let store: WorkspaceStore

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
