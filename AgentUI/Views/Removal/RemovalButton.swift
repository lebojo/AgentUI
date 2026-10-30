import SwiftUI

struct RemovalButton: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store

    @Binding var pending: Removal?

    let removal: Removal
    let placement: Placement

    private var requiresConfirmation: Bool { settings.confirmations.requires(removal) }
    private var title: String {
        switch placement {
        case .menu: requiresConfirmation ? removal.actionTitle + "…" : removal.actionTitle
        case .swipe: removal.shortTitle
        }
    }
    private var role: ButtonRole? {
        switch placement {
        case .menu: .destructive
        case .swipe: nil
        }
    }

    var body: some View {
        Button(title, systemImage: removal.systemImage, role: role) { request() }
            .tint(Palette.danger)
            .disabled(store.isBusy(removal))
    }

    private func request() {
        if requiresConfirmation { pending = removal }
        else { store.remove(removal) }
    }

    enum Placement {
        case menu, swipe
    }
}
