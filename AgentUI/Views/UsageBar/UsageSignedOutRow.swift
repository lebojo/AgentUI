import SwiftUI

struct UsageSignedOutRow: View {
    let isWaiting: Bool
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(isWaiting ? "En attente de la connexion…" : "Usage des agents")
            Spacer(minLength: Spacing.xs)
            if isWaiting { ProgressView().controlSize(.mini) }
            else { Button("Se connecter…", action: showDetails).buttonStyle(.link) }
        }
        .font(Typography.s).foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
    }
}
