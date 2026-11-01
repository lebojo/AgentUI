import SwiftUI

struct RemovalConfirmation: View {
    @Environment(SettingsStore.self) private var settings

    @State private var skipsConfirmation = false

    @Binding var removal: Removal?

    let store: WorkspaceStore

    var body: some View {
        ZStack {
            dialog(allowingSkip: true)
                .dialogSuppressionToggle("Ne plus me demander", isSuppressed: $skipsConfirmation)
            dialog(allowingSkip: false)
        }
        .onChange(of: removal) { skipsConfirmation = false }
    }

    private func dialog(allowingSkip: Bool) -> some View {
        Color.clear.confirmationDialog(removal?.title ?? "", isPresented: isPresented(allowingSkip: allowingSkip), titleVisibility: .visible) {
            Button(removal?.confirmation ?? "", role: .destructive) { confirm() }
        } message: { Text(removal?.message ?? "") }
    }

    private func isPresented(allowingSkip: Bool) -> Binding<Bool> {
        Binding {
            removal?.allowsSkippingConfirmation == allowingSkip
        } set: { isPresented in
            if !isPresented { removal = nil }
        }
    }

    private func confirm() {
        guard let removal else { return }
        if skipsConfirmation { settings.confirmations.skip(removal) }
        store.remove(removal)
        self.removal = nil
    }
}
