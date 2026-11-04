import SwiftUI

struct TerminalLayoutView<Pane: View>: View {
    let layout: TerminalLayout
    @ViewBuilder let pane: (UUID) -> Pane

    var body: some View {
        switch layout {
        case .terminal(let id):
            pane(id)
                .id(id)
                .frame(minWidth: Dimension.Detail.paneMinLength, minHeight: Dimension.Detail.paneMinLength)
        case .split(.horizontal, let children):
            HSplitView {
                ForEach(children) { child in
                    TerminalLayoutView(layout: child, pane: pane)
                }
            }
        case .split(.vertical, let children):
            VSplitView {
                ForEach(children) { child in
                    TerminalLayoutView(layout: child, pane: pane)
                }
            }
        }
    }
}
