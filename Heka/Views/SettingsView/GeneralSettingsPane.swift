import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Ask for Confirmation") {
                Toggle("Before removing a project", isOn: $settings.confirmations.onProjectRemoval)
                Toggle("Before closing a terminal", isOn: $settings.confirmations.onTerminalClosing)
            }
            WorktreeFolderSettings()
        }
        .formStyle(.grouped)
    }
}
