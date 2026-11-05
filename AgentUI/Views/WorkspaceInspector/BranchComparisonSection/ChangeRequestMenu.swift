#if os(macOS)
import SwiftUI

struct ChangeRequestMenu: View {
    @Environment(\.openURL) private var openURL
    @Environment(InspectorStore.self) private var model
    @Environment(\.inspectedWorktree) private var worktree

    let base: ComparisonBranch
    let source: any InspectorSource

    private var branch: String? {
        model.local?.branch.flatMap { $0.isDetached ? nil : $0.name }
    }

    private var tracking: GitTracking? {
        model.local?.tracking
    }

    private var hosting: GitHosting? {
        model.local?.webAddress?.hosting
    }

    private var browserHelp: LocalizedStringKey {
        guard tracking?.isPublished == true else { return "Publish the branch first" }
        return tracking?.hasUnpushedCommits == true ? "Some local commits aren’t pushed yet" : "Open in Browser"
    }

    private var title: LocalizedStringKey {
        switch hosting {
        case .github: "Create Pull Request"
        case .gitlab: "Create Merge Request"
        case nil: "Create PR/MR"
        }
    }

    private var askAgentTitle: LocalizedStringKey {
        switch hosting {
        case .github: "Ask the Agent to Create the PR"
        case .gitlab: "Ask the Agent to Create the MR"
        case nil: "Ask the Agent to Create the PR/MR"
        }
    }

    private var terminalName: String {
        hosting == .gitlab ? String(localized: "Merge Request") : String(localized: "Pull Request")
    }

    var body: some View {
        if let branch {
            Menu(title, systemImage: "arrow.triangle.pull") {
                if let worktree {
                    Button(askAgentTitle, systemImage: "sparkles") {
                        source.runAgent(.changeRequest(base: base), name: terminalName, in: worktree)
                    }
                }
                if let url = model.local?.newChangeRequestURL(into: base) {
                    Button("Open in Browser", systemImage: "safari") { openURL(url) }
                        .disabled(tracking?.isPublished != true)
                        .help(browserHelp)
                }
            }
            .fixedSize()
        }
    }
}
#endif
