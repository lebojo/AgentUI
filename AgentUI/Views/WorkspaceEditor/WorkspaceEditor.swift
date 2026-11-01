import SwiftUI

enum WorkspaceSheet: Identifiable {
    case folder(parentID: UUID?)
    case rename(UUID, String)
    case worktree(UUID, String)
    case worktreeGroup(projectID: UUID, worktreeID: UUID?)
    var id: String {
        switch self {
        case .folder(let parentID): "folder-\(parentID?.uuidString ?? "root")"
        case .rename(let id, _): "rename-\(id)"
        case .worktree(let id, _): "worktree-\(id)"
        case .worktreeGroup(let projectID, let worktreeID): "worktree-group-\(projectID)-\(worktreeID?.uuidString ?? "empty")"
        }
    }
}

struct WorkspaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    @State private var name = ""
    @State private var submitting = false
    @State private var submission: Task<Void, Never>?
    @State private var error: String?
    @State private var appearance: SidebarAppearance?

    @FocusState private var focused: Bool

    let store: WorkspaceStore
    let sheet: WorkspaceSheet

    private var isWorktree: Bool { if case .worktree = sheet { true } else { false } }
    private var title: String {
        switch sheet {
        case .folder(nil): String(localized: "New Virtual Folder")
        case .folder: String(localized: "New Subfolder")
        case .rename: appearance == nil ? String(localized: "Rename") : String(localized: "Edit")
        case .worktree: String(localized: "New Worktree")
        case .worktreeGroup: String(localized: "New Worktree Group")
        }
    }
    private var explanation: String {
        switch sheet {
        case .folder: String(localized: "Gather projects from different places on your Mac. Their files stay where they are.")
        case .rename: appearance == nil ? String(localized: "This name will be shown in the sidebar.") : String(localized: "This name, icon and color will be shown in the sidebar.")
        case .worktree(_, let project): String(localized: "Opens the branch in a separate working folder. If it doesn’t exist yet, it’s created from HEAD of \(project). \(worktreeLaunchDescription)")
        case .worktreeGroup: String(localized: "Groups the project’s worktrees under one name in the sidebar. Their folders and branches don’t change.")
        }
    }

    private var placeholder: String {
        switch sheet {
        case .worktree: String(localized: "feature/my-task")
        case .worktreeGroup: String(localized: "Reviews")
        case .folder, .rename: String(localized: "My Projects")
        }
    }

    private var symbol: String {
        switch sheet {
        case .worktree: "arrow.triangle.branch"
        case .worktreeGroup: "rectangle.stack"
        case .folder, .rename: "pencil"
        }
    }

    private var worktreeLaunchDescription: String {
        settings.agentLaunch.launches(on: .newWorktree) ? String(localized: "\(settings.agentLaunch.agent.title) will be launched there.") : String(localized: "A terminal will be opened there.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: appearance?.displaySymbol.systemName ?? symbol)
                    .foregroundStyle(appearance?.color ?? Palette.accent)
            }
            .font(Typography.title)
            Text(explanation).foregroundStyle(Palette.textSecondary).font(Typography.body).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(isWorktree ? "Branch" : "Name").font(Typography.label)
                TextField(placeholder, text: $name)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { submit() }.disabled(submitting)
            }
            if let appearance = Binding($appearance) {
                SidebarAppearancePicker(appearance: appearance)
            }
            if let error {
                Text(error).font(Typography.body).foregroundStyle(Palette.danger).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if submitting { ProgressView().controlSize(.small); Text("Creating worktree…").font(Typography.caption).foregroundStyle(Palette.textSecondary) }
                Spacer()
                Button(submitting ? "Stop" : "Cancel") {
                    if submitting { submission?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button(isWorktree ? "Create Worktree" : "Save") { submit() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
            }
        }
        .padding(Spacing.xxl).frame(width: Dimension.Sheet.width)
        .interactiveDismissDisabled(submitting)
        .onAppear {
            switch sheet {
            case .folder: appearance = SidebarAppearance(kind: .folder)
            case .rename(let id, let current):
                name = current
                appearance = store.appearance(of: id)
            case .worktree, .worktreeGroup: break
            }
            focused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !submitting else { return }
        switch sheet {
        case .folder(let parentID):
            let id = store.addFolder(trimmed, parentID: parentID)
            if let appearance { store.setAppearance(appearance, for: id) }
            dismiss()
        case .rename(let id, _):
            store.rename(id, to: trimmed)
            if let appearance { store.setAppearance(appearance, for: id) }
            dismiss()
        case .worktreeGroup(let project, let worktree):
            store.addWorktreeGroup(trimmed, projectID: project, moving: worktree)
            dismiss()
        case .worktree(let project, _):
            submitting = true
            error = nil
            submission = Task {
                do { _ = try await store.createWorktree(projectID: project, branch: trimmed, command: settings.agentLaunch.command(on: .newWorktree)); dismiss() }
                catch is CancellationError { self.error = String(localized: "Creation cancelled.") }
                catch { self.error = error.localizedDescription }
                submitting = false
                submission = nil
            }
        }
    }
}
