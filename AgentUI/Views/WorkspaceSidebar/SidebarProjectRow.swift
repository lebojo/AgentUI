import SwiftUI
import AppKit

struct SidebarProjectRow: View {
    @Environment(SettingsStore.self) private var settings

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let project: Project
    let query: String
    let showAll: Bool

    var body: some View {
        DisclosureGroup(isExpanded: expanded(project.id)) {
            ForEach(project.worktrees.filter(\.isPrimary)) { worktree in
                ForEach(worktree.terminals.filter { showAll || matches(project.name) || matches($0.name) }) { terminal in
                    SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, worktree: worktree)
                }
                if worktree.terminals.isEmpty {
                    Button("Ouvrir un terminal") { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
                        .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            ForEach(project.worktreeGroups.filter { showAll || matches(project.name) || matches($0.name) || !visibleWorktrees(in: $0.id).isEmpty }) { group in
                SidebarWorktreeGroupRow(sheet: $sheet, removal: $removal, store: store, project: project, group: group, query: query,
                                        showAll: showAll || matches(project.name) || matches(group.name))
            }
            ForEach(visibleWorktrees(in: nil)) { worktree in
                SidebarWorktreeRow(sheet: $sheet, removal: $removal, store: store, project: project, worktree: worktree, query: query,
                                   showAll: showAll || matches(project.name))
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: project.appearance.displaySymbol.systemName).foregroundStyle(project.appearance.color)
                HStack(spacing: Spacing.xs) {
                    Text(project.name).lineLimit(1)
                    if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) {
                        Image(systemName: "moon").font(Typography.caption)
                    }
                }
                .foregroundStyle(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? Palette.textSecondary : Palette.textPrimary)
                .contentShape(Rectangle())
                .onTapGesture { activate(project) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { activate(project) }
                .help(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? "Projet en veille — cliquer pour ouvrir un terminal" : project.name)
                Spacer(minLength: Spacing.xxs)
                if store.busyProjects.contains(project.id) { ProgressView().controlSize(.mini) }
                else {
                    Button { sheet = .worktree(project.id, project.name) } label: { Image(systemName: "plus").font(Typography.s.weight(.semibold)) }
                        .buttonStyle(.borderless).help("Créer un worktree pour \(project.name)")
                        .accessibilityLabel("Créer un worktree pour \(project.name)")
                }
            }
            .contentShape(Rectangle())
            .help(project.path)
            .draggable(project.id.uuidString)
            .contextMenu {
                Button("Nouveau terminal", systemImage: "terminal") {
                    if let main = project.worktrees.first(where: \.isPrimary) { store.openTerminal(project, main, launch: settings.agentLaunch) }
                }
                Button("Nouveau worktree…", systemImage: "arrow.triangle.branch") { sheet = .worktree(project.id, project.name) }
                    .disabled(store.busyProjects.contains(project.id))
                Button("Nouveau groupe de worktrees…", systemImage: "rectangle.stack.badge.plus") { sheet = .worktreeGroup(projectID: project.id, worktreeID: nil) }
                Menu("Déplacer vers", systemImage: "folder") {
                    Button("Sans dossier") { store.moveProject(project.id, to: nil) }
                        .disabled(project.folderID == nil)
                    ForEach(store.folders.destinations()) { destination in
                        Button(destination.title) { store.moveProject(project.id, to: destination.id) }
                            .disabled(project.folderID == destination.id)
                    }
                }
                Button("Renommer et personnaliser…", systemImage: "paintpalette") { sheet = .rename(project.id, project.name) }
                Button("Afficher dans le Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }
                Button("Actualiser les worktrees", systemImage: "arrow.clockwise") { Task { await store.refreshWorktrees(project.id) } }
                    .disabled(store.busyProjects.contains(project.id))
                Divider()
                RemovalButton(pending: $removal, removal: .project(project.id), placement: .menu)
            }
            .swipeActions(edge: .trailing) {
                RemovalButton(pending: $removal, removal: .project(project.id), placement: .swipe)
            }
        }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
    private func expanded(_ id: UUID) -> Binding<Bool> {
        query.isEmpty ? $store[expanded: id] : .constant(true)
    }
    private func visibleWorktrees(in groupID: UUID?) -> [Worktree] {
        project.worktrees(in: groupID).filter { worktree in
            showAll || matches(project.name) || matches(worktree.name) || worktree.terminals.contains { matches($0.name) }
        }
    }
    private func activate(_ project: Project) {
        if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) { store.wakeProject(project.id) }
        else { store.setExpanded(project.id, !store.isExpanded(project.id)) }
    }
}
