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
    private var worktreeRemoval: Removal { .worktree(projectID: project.id, worktreeID: worktree.id, name: worktree.displayName) }
    private var isExpanded: Binding<Bool> {
        guard isInserted else { return .constant(false) }
        return query.isEmpty ? $store[expanded: worktree.id] : .constant(true)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(terminals) { terminal in
                SidebarTerminalRow(sheet: $sheet, removal: $removal, store: store, terminal: terminal, worktree: worktree)
            }
            .onMove(perform: store.isReadOnly ? nil : { store.reorderTerminals(in: worktree.id, terminals.map(\.id), from: $0, to: $1) })
            if worktree.terminals.isEmpty {
                Button("Open Terminal") { openTerminal() }
                    .buttonStyle(.plain).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.textSecondary)
                Text(worktree.displayName).lineLimit(1)
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
