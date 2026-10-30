import SwiftUI

struct HostSettingsPane: View {
    @Environment(LocalHost.self) private var host

    var body: some View {
        @Bindable var host = host
        Form {
            Section {
                Toggle("Autoriser l’accès depuis le réseau local", isOn: $host.enabled)
                Text(host.status).foregroundStyle(Palette.textSecondary)
                if host.enabled {
                    ForEach(host.addresses, id: \.self) { address in
                        LabeledContent("IP du Mac", value: address).textSelection(.enabled)
                    }
                    LabeledContent("Code d’appairage") {
                        Text(host.pairingCode).font(Typography.body.monospaced()).textSelection(.enabled)
                    }
                }
            } header: { Text("iPhone et iPad") } footer: {
                Text("Sur le même réseau, saisis cette IP et ce code dans les réglages de l’app mobile. Le Mac doit rester allumé avec AgentUI ouvert.")
            }
            Section {
                Button("Générer un nouveau code") { host.renewPairingCode() }
                    .disabled(!host.enabled)
                if let error = host.pairingStorageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                }
            } footer: {
                Text("Seuls les appareils qui connaissent ce code peuvent lire les projets et contrôler les terminaux. Les échanges sont chiffrés avec ce code. Génère un nouveau code pour révoquer les appareils déjà appairés.")
            }
        }.formStyle(.grouped)
    }
}
