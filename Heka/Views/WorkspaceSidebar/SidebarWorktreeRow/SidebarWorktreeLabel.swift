import AppKit
import SwiftUI

struct SidebarWorktreeLabel: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    let projectID: UUID
    let worktreeGroups: [WorktreeGroup]
    let worktreeID: UUID
    let name: String
    let displayName: String
    let path: String
    let groupID: UUID?

    private var branch: GitBranch? { store.sessions.branch(at: path) }
    private var worktreeRemoval: Removal { .worktree(projectID: projectID, worktreeID: worktreeID, name: displayName) }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
            Text(displayName).lineLimit(1).layoutPriority(1)
            if let branch, branch.name != name {
                SidebarBranchName(branch: branch, color: Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xxs)
            Button { openTerminal() } label: { Image(systemName: "plus").font(Typography.xs.weight(.semibold)) }
                .buttonStyle(.borderless).help("New terminal in \(displayName)")
                .accessibilityLabel("New terminal in \(displayName)")
        }
        .help(path)
        .draggable(worktreeID.uuidString)
        .contextMenu {
            Button("New Terminal", systemImage: "terminal") { openTerminal() }
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
            Menu("Group", systemImage: "rectangle.stack") {
                Button("No Group") { store.moveWorktree(worktreeID, to: nil) }
                    .disabled(groupID == nil)
                ForEach(worktreeGroups) { group in
                    Button(group.name) { store.moveWorktree(worktreeID, to: group.id) }
                        .disabled(groupID == group.id)
                }
                Divider()
                Button("New Group…") { presentation.sheet = .worktreeGroup(projectID: projectID, worktreeID: worktreeID) }
            }
            Divider()
            RemovalButton(removal: worktreeRemoval, placement: .menu)
        }
        .swipeActions(edge: .trailing) {
            RemovalButton(removal: worktreeRemoval, placement: .swipe)
        }
    }

    private func openTerminal() { store.openTerminal(projectID: projectID, worktreeID: worktreeID, launch: settings.agentLaunch) }
}
