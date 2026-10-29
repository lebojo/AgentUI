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
                    SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, path: worktree.path)
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
                Button("Retirer le projet…", systemImage: "minus.circle", role: .destructive) { removal = .project(project.id) }
                    .disabled(store.busyProjects.contains(project.id))
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

private struct SidebarWorktreeGroupRow: View {
    @State private var isDropTargeted = false

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let project: Project
    let group: WorktreeGroup
    let query: String
    let showAll: Bool

    private var worktrees: [Worktree] {
        project.worktrees(in: group.id).filter { worktree in
            showAll || matches(worktree.name) || worktree.terminals.contains { matches($0.name) }
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? $store[expanded: group.id] : .constant(true)) {
            ForEach(worktrees) { worktree in
                SidebarWorktreeRow(sheet: $sheet, removal: $removal, store: store, project: project, worktree: worktree, query: query, showAll: showAll)
            }
            if project.worktrees(in: group.id).isEmpty {
                Text("Glisse un worktree ici").font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "rectangle.stack").foregroundStyle(Palette.textSecondary)
                Text(group.name).lineLimit(1)
                Spacer(minLength: Spacing.xxs)
                Text("\(project.worktrees(in: group.id).count)")
                    .font(Typography.caption).monospacedDigit().foregroundStyle(Palette.textSecondary)
            }
            .contentShape(Rectangle())
            .background(Palette.accent.opacity(isDropTargeted ? 0.2 : 0), in: RoundedRectangle(cornerRadius: Radius.s))
            .help(group.name)
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, let id = UUID(uuidString: value) else { return false }
                return store.moveWorktree(id, to: group.id)
            } isTargeted: { isDropTargeted = $0 }
            .contextMenu {
                Button("Renommer…", systemImage: "pencil") { sheet = .rename(group.id, group.name) }
                Divider()
                Button("Dissoudre le groupe", systemImage: "rectangle.stack.badge.minus") { store.removeWorktreeGroup(group.id) }
            }
        }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
}

private struct SidebarWorktreeRow: View {
    @Environment(SettingsStore.self) private var settings

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let project: Project
    let worktree: Worktree
    let query: String
    let showAll: Bool

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? $store[expanded: worktree.id] : .constant(true)) {
            ForEach(worktree.terminals.filter { showAll || matches(worktree.name) || matches($0.name) }) { terminal in
                SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, path: worktree.path)
            }
            if worktree.terminals.isEmpty {
                Button("Ouvrir un terminal") { openTerminal() }
                    .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
                Text(worktree.name).lineLimit(1)
                Spacer(minLength: Spacing.xxs)
                Button { openTerminal() } label: { Image(systemName: "plus").font(Typography.xs.weight(.semibold)) }
                    .buttonStyle(.borderless).help("Nouveau terminal dans \(worktree.name)")
                    .accessibilityLabel("Nouveau terminal dans \(worktree.name)")
            }
            .help(worktree.path)
            .draggable(worktree.id.uuidString)
            .contextMenu {
                Button("Nouveau terminal", systemImage: "terminal") { openTerminal() }
                Button("Afficher dans le Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path) }
                Menu("Groupe", systemImage: "rectangle.stack") {
                    Button("Aucun groupe") { store.moveWorktree(worktree.id, to: nil) }
                        .disabled(worktree.groupID == nil)
                    ForEach(project.worktreeGroups) { group in
                        Button(group.name) { store.moveWorktree(worktree.id, to: group.id) }
                            .disabled(worktree.groupID == group.id)
                    }
                    Divider()
                    Button("Nouveau groupe…") { sheet = .worktreeGroup(projectID: project.id, worktreeID: worktree.id) }
                }
                Divider()
                Button("Supprimer le worktree…", systemImage: "trash", role: .destructive) { confirmDeletion() }
                    .disabled(store.busyProjects.contains(project.id))
            }
            .swipeActions(edge: .trailing) {
                Button("Supprimer", systemImage: "trash") { confirmDeletion() }
                    .tint(Palette.danger)
                    .disabled(store.busyProjects.contains(project.id))
            }
        }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
    private func openTerminal() { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
    private func confirmDeletion() {
        removal = .worktree(projectID: project.id, worktreeID: worktree.id, name: worktree.name)
    }
}

private extension WorkspaceStore {
    func openTerminal(_ project: Project, _ worktree: Worktree, launch: AgentLaunch) {
        do {
            _ = try addTerminal(projectID: project.id, worktreeID: worktree.id, command: launch.command(on: .newTerminal))
        }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SidebarTerminalRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let store: WorkspaceStore
    let terminal: TerminalRecord
    let path: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "terminal").font(Typography.m).foregroundStyle(Palette.textSecondary)
            Text(terminal.name).lineLimit(1)
            Spacer(minLength: Spacing.xs)
            if let branch = store.sessions.branch(for: terminal.id, initialPath: path) {
                BranchBadge(branch: branch).frame(maxWidth: Dimension.Badge.sidebarMaxWidth)
            }
            if let session = store.sessions.session(terminal.id) {
                Image(systemName: session.hasExited ? "circle" : "circle.fill")
                    .font(Typography.statusDot).foregroundStyle(session.hasExited ? Palette.textSecondary : Palette.success)
                    .accessibilityLabel(session.hasExited ? "Session terminée" : "Terminal ouvert")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .tag(terminal.id)
        .help(terminal.name)
        .contextMenu {
            Button("Renommer…", systemImage: "pencil") { sheet = .rename(terminal.id, terminal.name) }
            if terminal.hasCustomName {
                Button("Utiliser le nom de la conversation", systemImage: "bubble.left") { store.useAutomaticName(terminal.id) }
            }
            Divider()
            Button("Fermer le terminal…", systemImage: "xmark", role: .destructive) { removal = .terminal(terminal.id) }
        }
    }
}
