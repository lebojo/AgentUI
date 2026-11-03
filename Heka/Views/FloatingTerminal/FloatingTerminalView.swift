import SwiftUI

struct FloatingTerminalView: View {
    @Environment(FloatingTerminalStore.self) private var floating

    var body: some View {
        VStack(spacing: 0) {
            FloatingTerminalTabBar()
            Divider()
            if let tab = floating.state.selectedTab, let focusedID = floating.state.focusedID {
                TerminalLayoutView(layout: tab.layout) { id in
                    FloatingTerminalPane(id: id, isFocused: id == focusedID, isSplit: tab.layout.isSplit)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                TerminalFooter(session: floating.session(focusedID), path: floating.directory(of: focusedID))
            } else {
                Spacer()
            }
        }
        .background(Palette.surface)
        .background { FloatingTerminalWindowReader() }
        .previewSheetFrame(idealWidth: Dimension.FloatingTerminal.idealWidth, idealHeight: Dimension.FloatingTerminal.idealHeight)
        .onAppear { floating.prepare() }
    }
}
