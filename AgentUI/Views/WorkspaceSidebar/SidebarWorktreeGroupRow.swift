import SwiftUI
import AppKit

struct SidebarWorktreeGroupRow: View {
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
