import SwiftUI

struct SessionDisplaySettingsSection: View {
    @Binding var mode: SessionDisplayMode

    var body: some View {
        Section {
            Picker("Session Mode", selection: $mode) {
                ForEach(SessionDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }.pickerStyle(.segmented)
        } header: {
            Text("Session Display")
        } footer: {
            Text("Chat shows the Claude Code conversation. Terminal gives access to the full display, menus and permissions. Switching modes keeps the current session.")
        }
    }
}
