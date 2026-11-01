import SwiftUI

struct RepositoryImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<String>
    @State private var flattened = false

    let store: WorkspaceStore
    let plan: RepositoryImport

    private var total: Int { plan.repositoryPaths.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Label {
                Text("Importer « \(plan.destinationName) »")
            } icon: {
                Image(systemName: "square.and.arrow.down").foregroundStyle(Palette.accent)
            }
            .font(Typography.title)
            Text("\(total) dépôts Git trouvés. Choisis ceux à ajouter : les dossiers virtuels reprennent l’arborescence sur le disque. Les fichiers restent à leur emplacement.")
                .font(Typography.body).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $flattened) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Tout importer au même niveau").font(Typography.label)
                    Text("Un seul dossier « \(plan.destinationName) », sans sous-dossiers.")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            .toggleStyle(.switch)
            List {
                RepositoryImportRow(selection: $selection, item: plan.preview(flattened: flattened))
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(height: Dimension.ImportSheet.listHeight)
            if let warning = plan.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Typography.caption).foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                Text("\(selection.count) sur \(total) sélectionnés")
                    .font(Typography.caption).monospacedDigit().foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Importer") { submit() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || store.isImporting)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: Dimension.ImportSheet.width)
    }

    init(store: WorkspaceStore, plan: RepositoryImport) {
        self.store = store
        self.plan = plan
        _selection = State(initialValue: Set(plan.repositoryPaths))
    }

    private func submit() {
        let paths = selection
        let flattened = flattened
        Task { await store.importRepositories(plan, keeping: paths, flattened: flattened) }
        dismiss()
    }
}
