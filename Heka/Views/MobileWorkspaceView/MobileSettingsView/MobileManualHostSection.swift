import SwiftUI

struct MobileManualHostSection: View {
    @Environment(MobileWorkspaceStore.self) private var store

    @State private var address = ""
    @State private var pairingCode = ""
    @State private var error: String?

    private var isIncomplete: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairingCode.isEmpty
    }

    var body: some View {
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
            if let error { Text(error).foregroundStyle(Palette.danger) }
            Button("Connect", action: connect).disabled(isIncomplete)
        } header: { Text("Add Manually") } footer: {
            Text("Enter the IP address and pairing code shown on the Mac in Settings → Local Access.")
        }
    }

    private func connect() {
        do {
            try store.connect(to: address, pairingCode: pairingCode)
            address = ""
            pairingCode = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
