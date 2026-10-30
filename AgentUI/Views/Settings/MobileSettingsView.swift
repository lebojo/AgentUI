import SwiftUI

struct MobileSettingsView: View {
    @AppStorage("mobileSessionDisplayMode") private var mode: SessionDisplayMode = .chat

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var pairingCode = ""
    @State private var error: String?

    let store: MobileWorkspaceStore

    var body: some View {
        NavigationStack {
            Form {
                SessionDisplaySettingsSection(mode: $mode)
                Section {
                    TextField("IP du Mac, p. ex. 192.168.1.42", text: $address)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Adresse IP du Mac")
                    TextField("Code d’appairage, p. ex. ABCD-EFGH-JKLM", text: $pairingCode)
                        .font(Typography.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Code d’appairage")
                    if store.status == .connecting {
                        HStack { ProgressView(); Text("Connexion au Mac…") }
                    } else { Text(store.statusText).foregroundStyle(Palette.textSecondary) }
                    if let error { Text(error).foregroundStyle(Palette.danger) }
                    Button(store.isConnected ? "Reconnecter" : "Se connecter") {
                        do { try store.connect(to: address, pairingCode: pairingCode); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairingCode.isEmpty || store.status == .connecting)
                    if store.wantsConnection {
                        Button("Se déconnecter", role: .destructive) { store.disconnect() }
                    }
                } header: { Text("Mac hôte") } footer: {
                    Text("Sur le Mac, active Réglages → Accès local puis recopie son IP et son code d’appairage. Les deux appareils doivent être sur le même réseau. La session continue sur le Mac lorsque tu quittes l’app mobile.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
            .onAppear {
                address = store.host
                pairingCode = store.pairingCode
            }
        }
    }
}
