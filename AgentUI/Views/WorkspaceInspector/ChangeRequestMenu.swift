#if os(macOS)
import SwiftUI

struct ChangeRequestMenu: View {
    @Environment(\.openURL) private var openURL
    @Environment(WorkspaceStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @State private var branch: String?
    @State private var address: RemoteWebAddress?

    let root: String
    let base: ComparisonBranch

    private var title: LocalizedStringKey {
        switch address?.hosting {
        case .github: "Create Pull Request"
        case .gitlab: "Create Merge Request"
        case nil: "Create PR/MR"
        }
    }

    private var askAgentTitle: LocalizedStringKey {
        switch address?.hosting {
        case .github: "Ask the Agent to Create the PR"
        case .gitlab: "Ask the Agent to Create the MR"
        case nil: "Ask the Agent to Create the PR/MR"
        }
    }

    private var terminalName: String {
        address?.hosting == .gitlab ? String(localized: "Merge Request") : String(localized: "Pull Request")
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let branch {
                Menu(title, systemImage: "arrow.triangle.pull") {
                    Button(askAgentTitle, systemImage: "sparkles") { askAgent() }
                    if let url = address?.newChangeRequestURL(branch: branch, base: base.hostedName) {
                        Button("Open in Browser", systemImage: "safari") { openURL(url) }
                    }
                }
                .fixedSize()
            }
        }
        .task(id: root) { await load() }
    }

    private func load() async {
        let found = await GitRepository.repositories(containing: [root]).first?.branch
        let remote = await InspectorService.remoteURL(at: root)
        guard !Task.isCancelled else { return }
        branch = found.flatMap { $0.isDetached ? nil : $0.name }
        address = remote.flatMap(RemoteWebAddress.init(remoteURL:))
    }

    private func askAgent() {
        guard let context = store.selectedContext,
              let project = store.projects.first(where: { $0.id == context.project.id }),
              let worktree = project.worktrees.first(where: { $0.id == context.worktree.id }) else { return }
        store.runAgent(prompt: settings.prompts.changeRequest, name: terminalName, in: project, worktree, launch: settings.agentLaunch)
    }
}
#endif
