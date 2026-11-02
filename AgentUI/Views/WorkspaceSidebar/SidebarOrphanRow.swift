import SwiftUI
import AppKit

struct SidebarOrphanRow: View {
    @Environment(WorkspaceStore.self) private var store

    @Binding var removal: Removal?

    let worktree: DiscoveredWorktree

    private var trash: Removal { .orphanWorktree(path: worktree.path, name: worktree.folderName) }
    private var repositoryTitle: String {
        String(localized: "Add “\(worktree.repositoryName ?? "")” as Project")
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(worktree.folderName).lineLimit(1)
                if let branch = worktree.branch {
                    Text(branch).font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .help(worktree.path)
        .contextMenu {
            if worktree.hasRepository {
                Button(repositoryTitle, systemImage: "folder.badge.plus") { store.addRepository(of: worktree) }
                    .disabled(store.isReadOnly)
            }
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path) }
            Divider()
            RemovalButton(pending: $removal, removal: trash, placement: .menu)
        }
        .swipeActions(edge: .trailing) {
            RemovalButton(pending: $removal, removal: trash, placement: .swipe)
        }
    }
}
