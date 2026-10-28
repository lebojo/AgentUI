import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TerminalSettingsPane()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AgentSettingsPane()
                .tabItem { Label("Agents", systemImage: "sparkles") }
        }
        .frame(width: Dimension.Settings.width)
        .frame(minHeight: Dimension.Settings.minHeight, idealHeight: Dimension.Settings.idealHeight)
    }
}
