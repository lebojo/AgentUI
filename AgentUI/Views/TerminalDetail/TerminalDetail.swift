import AppKit
import SwiftUI

struct TerminalDetail: View {
    let store: WorkspaceStore
    let context: TerminalContext

    private var layout: TerminalLayout { store.layout(for: context.terminal.id) }

    var body: some View {
        VStack(spacing: 0) {
            TerminalHeader(store: store, context: context)

            Divider()

            TerminalLayoutView(layout: layout) { id in
                if let pane = store.context(for: id) {
                    TerminalPane(store: store, context: pane, isFocused: id == context.terminal.id, isSplit: layout.isSplit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            TerminalFooter(session: store.sessions.session(context.terminal.id), path: context.worktree.path)
        }
        .background(Palette.surface)
        .navigationTitle(context.terminal.name)
    }
}
