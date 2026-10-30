import SwiftUI

struct WorkspaceInspector: View {
    @AppStorage("inspectorTab") private var tab: InspectorTab = .files

    let context: TerminalContext?
    let source: any InspectorSource

    var body: some View {
        Group {
            if let context {
                InspectorContents(context: context, tab: tab, source: source)
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
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.s)
        }
    }
}

private struct InspectorContents: View {
    @Environment(\.workspaceVisible) private var workspaceVisible
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = InspectorStore()
    @State private var previews = InspectorPreviews()
    @State private var refresh = 0

    let context: TerminalContext
    let tab: InspectorTab
    let source: any InspectorSource

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(refresh: $refresh, model: model, title: tab.title,
                            subtitle: context.worktree.isPrimary ? context.project.name : context.worktree.name,
                            path: context.worktree.path)
            Divider()
            switch tab {
            case .files:
                List {
                    ExplorerDirectory(url: URL(fileURLWithPath: context.worktree.path), source: source)
                }.listStyle(.plain).id(refresh)
            case .agents: AgentConversationList(context: context, refresh: refresh, source: source)
            case .git, .checks: InspectorRepositoryContent(model: model, tab: tab)
            }
        }
        .environment(previews)
        .modifier(InspectorPreviewPresenter(previews: previews, source: source))
        .task(id: "\(tab.rawValue)-\(refresh)-\(workspaceVisible)-\(scenePhase == .background)", priority: .utility) {
            guard workspaceVisible, scenePhase != .background, tab == .git || tab == .checks else { return }
            let changes = await source.repositoryChanges(at: context.worktree.path)
            await model.monitor(path: context.worktree.path, forceRemote: refresh > 0, changes: changes,
                                readLocal: { [source] in try await source.localGit(at: $0) },
                                readRemote: { [source] in try await source.remote($0) })
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

private struct WorkspaceVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var workspaceVisible: Bool {
        get { self[WorkspaceVisibleKey.self] }
        set { self[WorkspaceVisibleKey.self] = newValue }
    }
}
