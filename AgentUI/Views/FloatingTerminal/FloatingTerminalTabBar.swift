import SwiftUI

struct FloatingTerminalTabBar: View {
    @Environment(FloatingTerminalStore.self) private var floating

    var body: some View {
        HStack(spacing: Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(floating.state.tabs) { tab in
                        FloatingTerminalTab(tab: tab, isSelected: tab.id == floating.state.selectedTab?.id)
                    }
                }
            }
            Button { floating.openTab() } label: { Image(systemName: "plus") }
                .help("New Tab (⌘T)")
                .accessibilityLabel("New tab")
                .keyboardShortcut("t")
            Divider().frame(height: IconSize.s)
            Button { floating.split(.horizontal) } label: { Image(systemName: "rectangle.split.2x1") }
                .help("Split Right (⌘D)")
                .accessibilityLabel("Split terminal right")
                .keyboardShortcut("d")
            Button { floating.split(.vertical) } label: { Image(systemName: "rectangle.split.1x2") }
                .help("Split Down (⇧⌘D)")
                .accessibilityLabel("Split terminal down")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider().frame(height: IconSize.s)
            Button("Done") { floating.isPresented = false }
        }
        .buttonStyle(.borderless)
        .font(Typography.m)
        .padding(.horizontal, Spacing.m)
        .frame(height: Dimension.FloatingTerminal.tabBarHeight)
        .background {
            Group {
                Button("Previous Tab") { floating.selectTab(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Tab") { floating.selectTab(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
