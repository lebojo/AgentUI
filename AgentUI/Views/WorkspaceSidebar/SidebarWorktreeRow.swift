import SwiftUI
import AppKit

struct SidebarWorktreeRow: View {
    @Environment(SettingsStore.self) private var settings

    @State private var isInserted = false

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    @Bindable var store: WorkspaceStore

    let project: Project
    let worktree: Worktree
    let query: String
    let showAll: Bool

    private var terminals: [TerminalRecord] {
        worktree.terminals.filter { showAll || matches(worktree.displayName) || matches($0.name) }
    }
    private var branch: GitBranch? { store.sessions.branchesByPath[worktree.path] }
    private var worktreeRemoval: Removal { .worktree(projectID: project.id, worktreeID: worktree.id, name: worktree.displayName) }
    private var isExpanded: Binding<Bool> {
        guard isInserted else { return .constant(false) }
        return query.isEmpty ? $store[expanded: worktree.id] : .constant(true)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            SidebarTerminalList(sheet: $sheet, removal: $removal, store: store, worktree: worktree, terminals: terminals)
            if worktree.terminals.isEmpty {
                Button("Open Terminal") { openTerminal() }
                    .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
                Text(worktree.displayName).lineLimit(1).layoutPriority(1)
                if let branch, branch.name != worktree.name {
                    SidebarBranchName(branch: branch, color: Palette.textSecondary)
                }
                Spacer(minLength: Spacing.xxs)
                Button { openTerminal() } label: { Image(systemName: "plus").font(Typography.xs.weight(.semibold)) }
                    .buttonStyle(.borderless).help("New terminal in \(worktree.displayName)")
                    .accessibilityLabel("New terminal in \(worktree.displayName)")
            }
            .help(worktree.path)
            .draggable(worktree.id.uuidString)
            .contextMenu {
                Button("New Terminal", systemImage: "terminal") { openTerminal() }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path) }
                Menu("Group", systemImage: "rectangle.stack") {
                    Button("No Group") { store.moveWorktree(worktree.id, to: nil) }
                        .disabled(worktree.groupID == nil)
                    ForEach(project.worktreeGroups) { group in
                        Button(group.name) { store.moveWorktree(worktree.id, to: group.id) }
                            .disabled(worktree.groupID == group.id)
                    }
                    Divider()
                    Button("New Group…") { sheet = .worktreeGroup(projectID: project.id, worktreeID: worktree.id) }
                }
                Divider()
                RemovalButton(pending: $removal, removal: worktreeRemoval, placement: .menu)
            }
            .swipeActions(edge: .trailing) {
                RemovalButton(pending: $removal, removal: worktreeRemoval, placement: .swipe)
            }
        }
        .task { isInserted = true }
    }

    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedStandardContains(query) }
    private func openTerminal() { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
}
