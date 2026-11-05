import AppKit
import SwiftUI

struct SidebarProjectMenu: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    let project: Project

    private var isBusy: Bool { store.busyProjects.contains(project.id) }

    var body: some View {
        Button("New Terminal", systemImage: "terminal") {
            if let main = project.worktrees.first(where: \.isPrimary) { store.openTerminal(project, main, launch: settings.agentLaunch) }
        }
        Button("New Worktree…", systemImage: "arrow.triangle.branch") { presentation.sheet = .worktree(project.id, project.name) }
            .disabled(isBusy)
        Button("New Worktree Group…", systemImage: "rectangle.stack.badge.plus") { presentation.sheet = .worktreeGroup(projectID: project.id, worktreeID: nil) }
        Menu("Move To", systemImage: "folder") {
            Button("No Folder") { store.moveProject(project.id, to: nil) }
                .disabled(project.folderID == nil)
            ForEach(store.folders.destinations()) { destination in
                Button(destination.title) { store.moveProject(project.id, to: destination.id) }
                    .disabled(project.folderID == destination.id)
            }
        }
        Button("Rename and Customize…", systemImage: "paintpalette") { presentation.sheet = .rename(project.id, project.name) }
        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }
        Button("Refresh Worktrees", systemImage: "arrow.clockwise") { Task { await store.refreshWorktrees(project.id) } }
            .disabled(isBusy)
        Divider()
        RemovalButton(removal: .project(project.id), placement: .menu)
    }
}
