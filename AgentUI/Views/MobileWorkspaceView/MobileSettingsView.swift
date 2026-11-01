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
                    TextField("Mac IP address, e.g. 192.168.1.42", text: $address)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Mac IP Address")
                    TextField("Pairing code, e.g. ABCD-EFGH-JKLM", text: $pairingCode)
                        .font(Typography.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Pairing Code")
                    if store.status == .connecting {
                        HStack { ProgressView(); Text("Connecting to the Mac…") }
                    } else { Text(store.statusText).foregroundStyle(Palette.textSecondary) }
                    if let error { Text(error).foregroundStyle(Palette.danger) }
                    Button(store.isConnected ? "Reconnect" : "Connect") {
                        do { try store.connect(to: address, pairingCode: pairingCode); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairingCode.isEmpty)
                    if store.wantsConnection {
                        Button("Disconnect", role: .destructive) { store.disconnect() }
                    }
                } header: { Text("Host Mac") } footer: {
                    Text("On the Mac, turn on Settings → Local Access, then copy its IP address and pairing code. Both devices must be on the same network. The session continues on the Mac when you leave the mobile app.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                address = store.host
                pairingCode = store.pairingCode
            }
        }
    }
}
