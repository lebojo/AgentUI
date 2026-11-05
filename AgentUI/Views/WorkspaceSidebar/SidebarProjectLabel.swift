import SwiftUI

struct SidebarProjectLabel: View {
    @Environment(WorkspaceStore.self) private var store

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let project: Project

    private var isIdle: Bool { project.worktrees.allSatisfy { $0.terminals.isEmpty } }
    private var primaryBranch: GitBranch? {
        project.worktrees.first(where: \.isPrimary).flatMap { store.sessions.branchesByPath[$0.path] }
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: project.appearance.displaySymbol.systemName).foregroundStyle(project.appearance.color)
            HStack(spacing: Spacing.xs) {
                Text(project.name).lineLimit(1).layoutPriority(1)
                if isIdle {
                    Image(systemName: "moon").font(Typography.caption)
                }
                if let primaryBranch {
                    SidebarBranchName(branch: primaryBranch, color: Palette.textSecondary)
                }
            }
            .foregroundStyle(isIdle ? Palette.textSecondary : Palette.textPrimary)
            .contentShape(Rectangle())
            .onTapGesture { activate() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .help(isIdle ? String(localized: "Idle project — click to open a terminal") : project.name)
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
        .contextMenu { SidebarProjectMenu(sheet: $sheet, removal: $removal, project: project) }
        .swipeActions(edge: .trailing) {
            RemovalButton(pending: $removal, removal: .project(project.id), placement: .swipe)
        }
    }

    private func activate() {
        if isIdle { store.wakeProject(project.id) }
        else { store.setExpanded(project.id, !store.isExpanded(project.id)) }
    }
}
