import SwiftUI

struct SidebarWorktreeGroupRow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    @State private var isDropTargeted = false

    let project: Project
    let group: WorktreeGroup
    let query: String
    let showAll: Bool

    private var worktrees: [Worktree] {
        project.worktrees(in: group.id).filter { worktree in
            showAll || matches(worktree.displayName) || worktree.terminals.contains { matches($0.name) }
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: query.isEmpty ? Bindable(store)[expanded: group.id] : .constant(true)) {
            ForEach(worktrees) { worktree in
                SidebarWorktreeRow(projectID: project.id, worktreeGroups: project.worktreeGroups, worktree: worktree, query: query, showAll: showAll)
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderWorktrees(in: project.id, worktrees.map(\.id), from: $0, to: $1) })
            if project.worktrees(in: group.id).isEmpty {
                Text("Drag a worktree here").font(Typography.caption).foregroundStyle(Palette.textSecondary)
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
            .background(isDropTargeted ? Palette.dropTargetFill : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
            .help(group.name)
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, let id = UUID(uuidString: value) else { return false }
                return store.moveWorktree(id, to: group.id)
            } isTargeted: { isDropTargeted = $0 }
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { presentation.sheet = .rename(group.id, group.name) }
                Divider()
                Button("Dissolve Group", systemImage: "rectangle.stack.badge.minus") { store.removeWorktreeGroup(group.id) }
            }
        }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
}
