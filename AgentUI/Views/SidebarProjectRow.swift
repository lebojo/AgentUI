import SwiftUI
import AppKit

struct SidebarProjectRow: View {
    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let project: Project
    let query: String
    let showAll: Bool

    var body: some View {
        DisclosureGroup(isExpanded: expanded(project.id)) {
            ForEach(project.worktrees) { worktree in
                if worktree.isPrimary {
                    ForEach(worktree.terminals.filter { showAll || matches(project.name) || matches($0.name) }) { terminal in
                        SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, path: worktree.path)
                    }
                    if worktree.terminals.isEmpty {
                        Button("Ouvrir un terminal") { addTerminal(project, worktree) }
                            .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    }
                } else if showAll || matches(project.name) || matches(worktree.name) || worktree.terminals.contains(where: { matches($0.name) }) {
                    DisclosureGroup(isExpanded: expanded(worktree.id)) {
                        ForEach(worktree.terminals.filter { showAll || matches(project.name) || matches(worktree.name) || matches($0.name) }) { terminal in
                            SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, path: worktree.path)
                        }
                        if worktree.terminals.isEmpty {
                            Button("Ouvrir un terminal") { addTerminal(project, worktree) }
                                .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                        }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
                            Text(worktree.name).lineLimit(1)
                            Spacer(minLength: Spacing.xxs)
                            Button { addTerminal(project, worktree) } label: { Image(systemName: "plus").font(Typography.xs.weight(.semibold)) }
                                .buttonStyle(.borderless).help("Nouveau terminal dans \(worktree.name)")
                                .accessibilityLabel("Nouveau terminal dans \(worktree.name)")
                        }
                        .help(worktree.path)
                        .contextMenu {
                            Button("Nouveau terminal", systemImage: "terminal") { addTerminal(project, worktree) }
                            Button("Afficher dans le Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: project.appearance.displaySymbol.systemName).foregroundStyle(project.appearance.color)
                Button {
                    if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) { store.wakeProject(project.id) }
                    else { store.setExpanded(project.id, !store.isExpanded(project.id)) }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(project.name).lineLimit(1)
                        if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) {
                            Image(systemName: "moon").font(Typography.caption)
                        }
                    }
                    .foregroundStyle(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? Palette.textSecondary : Palette.textPrimary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? "Projet en veille — cliquer pour ouvrir un terminal" : project.name)
                Spacer(minLength: Spacing.xxs)
                if store.busyProjects.contains(project.id) { ProgressView().controlSize(.mini) }
                else {
                    Button { sheet = .worktree(project.id, project.name) } label: { Image(systemName: "plus").font(Typography.s.weight(.semibold)) }
                        .buttonStyle(.borderless).help("Créer un worktree pour \(project.name)")
                        .accessibilityLabel("Créer un worktree pour \(project.name)")
                }
            }
            .help(project.path)
            .draggable(project.id.uuidString)
            .contextMenu {
                Button("Nouveau terminal", systemImage: "terminal") {
                    if let main = project.worktrees.first(where: \.isPrimary) { addTerminal(project, main) }
                }
                Button("Nouveau worktree…", systemImage: "arrow.triangle.branch") { sheet = .worktree(project.id, project.name) }
                    .disabled(store.busyProjects.contains(project.id))
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
    private func addTerminal(_ project: Project, _ worktree: Worktree) {
        do { _ = try store.addTerminal(projectID: project.id, worktreeID: worktree.id) }
        catch { store.errorMessage = error.localizedDescription }
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
            Divider()
            Button("Fermer le terminal…", systemImage: "xmark", role: .destructive) { removal = .terminal(terminal.id) }
        }
    }
}
