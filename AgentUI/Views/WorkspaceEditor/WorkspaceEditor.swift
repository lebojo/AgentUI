import SwiftUI

enum WorkspaceSheet: Identifiable {
    case folder(parentID: UUID?)
    case rename(UUID, String)
    case worktree(UUID, String)
    var id: String {
        switch self {
        case .folder(let parentID): "folder-\(parentID?.uuidString ?? "root")"
        case .rename(let id, _): "rename-\(id)"
        case .worktree(let id, _): "worktree-\(id)"
        }
    }
}

struct WorkspaceEditor: View {
    @Environment(\.dismiss) private var dismiss

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
        case .folder(nil): "Nouveau dossier virtuel"
        case .folder: "Nouveau sous-dossier"
        case .rename: appearance == nil ? "Renommer" : "Modifier"
        case .worktree: "Nouveau worktree"
        }
    }
    private var explanation: String {
        switch sheet {
        case .folder: "Réunis des projets situés à différents endroits sur ton Mac. Leurs fichiers restent en place."
        case .rename: appearance == nil ? "Ce nom sera affiché dans la barre latérale." : "Ce nom, cette icône et cette couleur seront affichés dans la barre latérale."
        case .worktree(_, let project): "Crée une nouvelle branche depuis HEAD de \(project), dans un dossier de travail séparé. Un terminal y sera ouvert."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: appearance?.displaySymbol.systemName ?? (isWorktree ? "arrow.triangle.branch" : "pencil"))
                    .foregroundStyle(appearance?.color ?? Palette.accent)
            }
            .font(Typography.title)
            Text(explanation).foregroundStyle(Palette.textSecondary).font(Typography.body).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(isWorktree ? "Nouvelle branche" : "Nom").font(Typography.label)
                TextField(isWorktree ? "feature/ma-tache" : "Mes projets", text: $name)
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
                if submitting { ProgressView().controlSize(.small); Text("Création du worktree…").font(Typography.caption).foregroundStyle(Palette.textSecondary) }
                Spacer()
                Button(submitting ? "Arrêter" : "Annuler") {
                    if submitting { submission?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button(isWorktree ? "Créer le worktree" : "Enregistrer") { submit() }
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
            case .worktree: break
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
        case .worktree(let project, _):
            submitting = true
            error = nil
            submission = Task {
                do { _ = try await store.createWorktree(projectID: project, branch: trimmed); dismiss() }
                catch is CancellationError { self.error = "Création annulée." }
                catch { self.error = error.localizedDescription }
                submitting = false
                submission = nil
            }
        }
    }
}
