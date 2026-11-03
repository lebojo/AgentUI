import SwiftUI

struct MobileSavedHostsSection: View {
    @Environment(MobileWorkspaceStore.self) private var store

    @State private var scannerVisible = false
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(store.savedHosts) { host in
                Button { select(host) } label: { MobileHostRow(host: host) }
            }
            .onDelete(perform: forget)
            if MobileQRScanner.isSupported {
                Button("Scan QR Code", systemImage: "qrcode.viewfinder") { scannerVisible = true }
            } else {
                Label("This device can’t scan QR codes. Add the Mac manually below.", systemImage: "qrcode")
                    .foregroundStyle(Palette.textSecondary)
            }
            if store.status == .connecting {
                HStack { ProgressView(); Text("Connecting to the Mac…") }
            } else if store.selectedHost != nil {
                Text(store.statusText).foregroundStyle(Palette.textSecondary)
            }
            if let error { Text(error).foregroundStyle(Palette.danger) }
            if store.wantsConnection {
                Button("Disconnect", role: .destructive) { store.disconnect() }
            }
        } header: { Text("Macs") } footer: {
            Text("On the Mac, turn on Settings → Local Access, then scan the QR code it shows. Tap a saved Mac to switch to it. Both devices must be on the same network. The session continues on the Mac when you leave the mobile app.")
        }
        .sheet(isPresented: $scannerVisible) {
            MobileScannerSheet().environment(store)
        }
    }

    private func select(_ host: SavedHost) {
        do {
            try store.select(host)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func forget(_ offsets: IndexSet) {
        do {
            for host in offsets.map({ store.savedHosts[$0] }) { try store.forget(host) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
