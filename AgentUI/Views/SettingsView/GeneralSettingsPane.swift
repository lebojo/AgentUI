import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Demander confirmation") {
                Toggle("Avant de retirer un projet", isOn: $settings.confirmations.onProjectRemoval)
                Toggle("Avant de fermer un terminal", isOn: $settings.confirmations.onTerminalClosing)
            }
        }
        .formStyle(.grouped)
    }
}
