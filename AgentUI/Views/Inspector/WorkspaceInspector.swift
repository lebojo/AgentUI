import SwiftUI

struct WorkspaceInspector: View {
    @AppStorage("inspectorTab") private var tab: InspectorTab = .files

    @Bindable var store: WorkspaceStore

    var body: some View {
        Group {
            if let context = store.selectedContext {
                InspectorContents(store: store, context: context, tab: tab)
                    .id(context.worktree.id)
            } else {
                ContentUnavailableView("Aucun terminal sélectionné", systemImage: tab.symbol,
                                       description: Text("Ouvre un terminal pour explorer son projet."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            Picker("Vue du panneau de droite", selection: $tab) {
                ForEach(InspectorTab.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(.iconOnly)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct InspectorContents: View {
    @Environment(AppVisibility.self) private var visibility

    @State private var model = InspectorStore()
    @State private var previews = InspectorPreviews()
    @State private var refresh = 0

    @Bindable var store: WorkspaceStore

    let context: TerminalContext
    let tab: InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(refresh: $refresh, model: model, title: tab.title,
                            subtitle: context.worktree.isPrimary ? context.project.name : context.worktree.name,
                            path: context.worktree.path)
            Divider()
            switch tab {
            case .files:
                List {
                    ExplorerDirectory(url: URL(fileURLWithPath: context.worktree.path))
                }.listStyle(.plain).id(refresh)
            case .agents: AgentConversationList(store: store, context: context, refresh: refresh)
            case .git, .checks: InspectorRepositoryContent(model: model, tab: tab)
            }
        }
        .environment(previews)
        .modifier(InspectorPreviewPresenter(previews: previews))
        .task(id: "\(tab.rawValue)-\(refresh)-\(visibility.isVisible)", priority: .utility) {
            guard visibility.isVisible, tab == .git || tab == .checks else { return }
            let changes = await FileEvents.repositoryChanges(at: context.worktree.path)
            await model.monitor(path: context.worktree.path, forceRemote: refresh > 0, changes: changes)
        }
    }
}

struct InspectorNotice: View {
    let title: String
    let message: String
    var symbol = "exclamationmark.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(title, systemImage: symbol).font(Typography.label)
            Text(message).font(Typography.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
        }
    }
}
