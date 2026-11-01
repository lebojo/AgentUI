import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("Général", systemImage: "gearshape") }
            TerminalSettingsPane()
                .tabItem { Label("Affichage", systemImage: "rectangle.split.2x1") }
            AgentSettingsPane()
                .tabItem { Label("Agents", systemImage: "sparkles") }
            HostSettingsPane()
                .tabItem { Label("Accès local", systemImage: "network") }
        }
        .frame(width: Dimension.Settings.width)
        .frame(minHeight: Dimension.Settings.minHeight, idealHeight: Dimension.Settings.idealHeight)
    }
}
