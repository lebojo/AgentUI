#if os(macOS)
import SwiftUI

struct ChangeRequestMenu: View {
    @Environment(\.openURL) private var openURL
    @Environment(InspectorStore.self) private var model

    @State private var address: RemoteWebAddress?

    let root: String
    let base: ComparisonBranch
    let context: TerminalContext
    let source: any InspectorSource

    private var branch: String? {
        model.local?.branch.flatMap { $0.isDetached ? nil : $0.name }
    }

    private var tracking: GitTracking? {
        model.local?.tracking
    }

    private var browserHelp: LocalizedStringKey {
        guard tracking?.isPublished == true else { return "Push the branch first" }
        return tracking?.hasUnpushedCommits == true ? "Some local commits aren’t pushed yet" : "Open in Browser"
    }

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
                    Button(askAgentTitle, systemImage: "sparkles") {
                        source.runAgent(prompt: \.changeRequest, name: terminalName, context: context)
                    }
                    if let url = address?.newChangeRequestURL(branch: branch, base: base.hostedName) {
                        Button("Open in Browser", systemImage: "safari") { openURL(url) }
                            .disabled(tracking?.isPublished != true)
                            .help(browserHelp)
                    }
                }
                .fixedSize()
            }
        }
        .task(id: root) {
            let remote = await InspectorService.remoteURL(at: root)
            guard !Task.isCancelled else { return }
            address = remote.flatMap(RemoteWebAddress.init(remoteURL:))
        }
    }
}
#endif
