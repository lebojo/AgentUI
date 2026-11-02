import SwiftUI

struct HostSettingsPane: View {
    @Environment(LocalHost.self) private var host

    var body: some View {
        @Bindable var host = host
        Form {
            Section {
                Toggle("Allow Access from the Local Network", isOn: $host.enabled)
                Text(host.status).foregroundStyle(Palette.textSecondary)
                if host.enabled {
                    ForEach(host.addresses, id: \.self) { address in
                        LabeledContent("Mac IP", value: address).textSelection(.enabled)
                    }
                    LabeledContent("Pairing Code") {
                        Text(host.pairingCode).font(Typography.body.monospaced()).textSelection(.enabled)
                    }
                }
            } header: { Text("iPhone and iPad") } footer: {
                Text("On the same network, enter this IP address and code in the mobile app’s settings. The Mac must stay on with AgentUI open.")
            }
            if let invitation = host.invitation {
                Section {
                    PairingQRCode(content: invitation.link)
                        .frame(maxWidth: .infinity)
                } header: { Text("Scan to Pair") } footer: {
                    Text("In the mobile app, open Settings, tap Scan QR Code, then point the camera at this code. The phone saves this Mac so you can switch back to it later.")
                }
            }
            Section {
                Button("Generate New Code") { host.renewPairingCode() }
                    .disabled(!host.enabled)
                if let error = host.pairingStorageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                }
            } footer: {
                Text("Only devices that know this code can read projects and control terminals. Traffic is encrypted with this code. Generate a new code to revoke devices that are already paired.")
            }
        }.formStyle(.grouped)
    }
}
