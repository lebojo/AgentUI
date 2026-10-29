import SwiftUI

struct TerminalLayoutView: View {
    let store: WorkspaceStore
    let layout: TerminalLayout
    let focusedID: UUID
    let isSplit: Bool

    var body: some View {
        switch layout {
        case .terminal(let id):
            if let context = store.context(for: id) {
                TerminalPane(store: store, context: context, isFocused: id == focusedID, isSplit: isSplit)
                    .id(id)
                    .frame(minWidth: Dimension.Detail.paneMinLength, minHeight: Dimension.Detail.paneMinLength)
            }
        case .split(.horizontal, let children):
            HSplitView {
                ForEach(children) { child in
                    TerminalLayoutView(store: store, layout: child, focusedID: focusedID, isSplit: isSplit)
                }
            }
        case .split(.vertical, let children):
            VSplitView {
                ForEach(children) { child in
                    TerminalLayoutView(store: store, layout: child, focusedID: focusedID, isSplit: isSplit)
                }
            }
        }
    }
}
