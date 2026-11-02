import SwiftUI

struct SubagentDetail: View {
    let store: WorkspaceStore
    let context: TerminalContext
    let subagent: Subagent

    var body: some View {
        VStack(spacing: 0) {
            SubagentHeader(store: store, context: context, subagent: subagent)

            Divider()

            SubagentTranscript(journal: subagent.journal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            TerminalFooter(session: store.sessions.session(context.terminal.id), path: context.worktree.path)
        }
        .background(Palette.surface)
        .navigationTitle(subagent.title)
    }
}
