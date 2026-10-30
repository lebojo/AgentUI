import SwiftUI

struct SessionDisplaySettingsSection: View {
    @Binding var mode: SessionDisplayMode

    var body: some View {
        Section {
            Picker("Mode de session", selection: $mode) {
                ForEach(SessionDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }.pickerStyle(.segmented)
        } header: {
            Text("Affichage des sessions")
        } footer: {
            Text("Chat affiche la conversation de Claude Code. Terminal donne accès à l’affichage complet, aux menus et aux autorisations. Changer de mode conserve la session en cours.")
        }
    }
}
