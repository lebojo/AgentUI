import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            TerminalSettingsPane()
                .tabItem { Label("Display", systemImage: "rectangle.split.2x1") }
            AgentSettingsPane()
                .tabItem { Label("Agents", systemImage: "sparkles") }
            HostSettingsPane()
                .tabItem { Label("Local Access", systemImage: "network") }
        }
        .frame(width: Dimension.Settings.width)
        .frame(minHeight: Dimension.Settings.minHeight, idealHeight: Dimension.Settings.idealHeight)
    }
}
