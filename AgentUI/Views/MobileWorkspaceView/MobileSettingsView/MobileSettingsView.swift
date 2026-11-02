import SwiftUI

struct MobileSettingsView: View {
    @AppStorage("mobileSessionDisplayMode") private var mode: SessionDisplayMode = .chat

    @Environment(\.dismiss) private var dismiss

    let store: MobileWorkspaceStore

    var body: some View {
        NavigationStack {
            Form {
                SessionDisplaySettingsSection(mode: $mode)
                MobileSavedHostsSection()
                MobileManualHostSection()
            }
            .environment(store)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
