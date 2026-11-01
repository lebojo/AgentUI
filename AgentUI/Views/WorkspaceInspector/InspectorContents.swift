import SwiftUI

struct InspectorContents: View {
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
