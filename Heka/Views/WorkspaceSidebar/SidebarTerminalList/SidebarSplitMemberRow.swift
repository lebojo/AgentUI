import SwiftUI

struct SidebarSplitMemberRow: View {
    @Environment(WorkspaceStore.self) private var store

    let terminal: TerminalRecord
    let isFocused: Bool

    var body: some View {
        Button { store.selection = terminal.id } label: {
            SidebarTerminalLabel(name: terminal.name, session: store.sessions.session(terminal.id))
                .fontWeight(isFocused ? .semibold : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .terminalDragSource(terminal.id)
        .contextMenu { SidebarTerminalMenu(terminal: terminal) }
    }
}
