import AppKit
import SwiftUI

struct SidebarWorktreeLabel: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    let project: Project
    let worktree: Worktree

    private var branch: GitBranch? { store.sessions.branchesByPath[worktree.path] }
    private var worktreeRemoval: Removal { .worktree(projectID: project.id, worktreeID: worktree.id, name: worktree.displayName) }

    var body: some View {
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
                Button("New Group…") { presentation.sheet = .worktreeGroup(projectID: project.id, worktreeID: worktree.id) }
            }
            Divider()
            RemovalButton(removal: worktreeRemoval, placement: .menu)
        }
        .swipeActions(edge: .trailing) {
            RemovalButton(removal: worktreeRemoval, placement: .swipe)
        }
    }

    private func openTerminal() { store.openTerminal(project, worktree, launch: settings.agentLaunch) }
}
