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

    private var visibleGroups: [WorktreeGroup] {
        project.worktreeGroups.filter { showAll || matches(project.name) || matches($0.name) || !visibleWorktrees(in: $0.id).isEmpty }
    }

    private var primaryBranch: GitBranch? {
        project.worktrees.first(where: \.isPrimary).flatMap { store.sessions.branchesByPath[$0.path] }
    }

    var body: some View {
        DisclosureGroup(isExpanded: expanded(project.id)) {
            ForEach(project.worktrees.filter(\.isPrimary)) { worktree in
                let terminals = worktree.terminals.filter { showAll || matches(project.name) || matches($0.name) }
                SidebarTerminalList(sheet: $sheet, removal: $removal, store: store, worktree: worktree, terminals: terminals)
                if worktree.terminals.isEmpty {
                    Button("Open Terminal") { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
                        .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            ForEach(visibleGroups) { group in
                SidebarWorktreeGroupRow(sheet: $sheet, removal: $removal, store: store, project: project, group: group, query: query,
                                        showAll: showAll || matches(project.name) || matches(group.name))
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderWorktreeGroups(in: project.id, visibleGroups.map(\.id), from: $0, to: $1) })
            let ungrouped = visibleWorktrees(in: nil)
            ForEach(ungrouped) { worktree in
                SidebarWorktreeRow(sheet: $sheet, removal: $removal, store: store, project: project, worktree: worktree, query: query,
                                   showAll: showAll || matches(project.name))
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderWorktrees(in: project.id, ungrouped.map(\.id), from: $0, to: $1) })
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: project.appearance.displaySymbol.systemName).foregroundStyle(project.appearance.color)
                HStack(spacing: Spacing.xs) {
                    Text(project.name).lineLimit(1).layoutPriority(1)
                    if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) {
                        Image(systemName: "moon").font(Typography.caption)
                    }
                    if let branch = primaryBranch {
                        SidebarBranchName(branch: branch, color: Palette.textSecondary)
                    }
                }
                .foregroundStyle(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? Palette.textSecondary : Palette.textPrimary)
                .contentShape(Rectangle())
                .onTapGesture { activate(project) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { activate(project) }
                .help(project.worktrees.allSatisfy({ $0.terminals.isEmpty }) ? String(localized: "Idle project — click to open a terminal") : project.name)
                Spacer(minLength: Spacing.xxs)
                if store.busyProjects.contains(project.id) { ProgressView().controlSize(.mini) }
                else {
                    Button { sheet = .worktree(project.id, project.name) } label: { Image(systemName: "plus").font(Typography.s.weight(.semibold)) }
                        .buttonStyle(.borderless).help("Create a worktree for \(project.name)")
                        .accessibilityLabel("Create a worktree for \(project.name)")
                }
            }
            .contentShape(Rectangle())
            .help(project.path)
            .draggable(project.id.uuidString)
            .contextMenu {
                Button("New Terminal", systemImage: "terminal") {
                    if let main = project.worktrees.first(where: \.isPrimary) { store.openTerminal(project, main, launch: settings.agentLaunch) }
                }
                Button("New Worktree…", systemImage: "arrow.triangle.branch") { sheet = .worktree(project.id, project.name) }
                    .disabled(store.busyProjects.contains(project.id))
                Button("New Worktree Group…", systemImage: "rectangle.stack.badge.plus") { sheet = .worktreeGroup(projectID: project.id, worktreeID: nil) }
                Menu("Move To", systemImage: "folder") {
                    Button("No Folder") { store.moveProject(project.id, to: nil) }
                        .disabled(project.folderID == nil)
                    ForEach(store.folders.destinations()) { destination in
                        Button(destination.title) { store.moveProject(project.id, to: destination.id) }
                            .disabled(project.folderID == destination.id)
                    }
                }
                Button("Rename and Customize…", systemImage: "paintpalette") { sheet = .rename(project.id, project.name) }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }
                Button("Refresh Worktrees", systemImage: "arrow.clockwise") { Task { await store.refreshWorktrees(project.id) } }
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
            showAll || matches(project.name) || matches(worktree.displayName) || worktree.terminals.contains { matches($0.name) }
        }
    }
    private func activate(_ project: Project) {
        if project.worktrees.allSatisfy({ $0.terminals.isEmpty }) { store.wakeProject(project.id) }
        else { store.setExpanded(project.id, !store.isExpanded(project.id)) }
    }
}
