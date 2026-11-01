import SwiftUI

struct UsageProviderSection: View {
    let provider: UsageProvider
    let state: UsageState
    let now: Date

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: Spacing.m) {
                ProgressView().controlSize(.small)
                Text("Chargement…").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
        case .signedOut:
            HStack(alignment: .center, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Non connecté").font(Typography.label)
                    Text(provider.signInHint).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                UsageSignInButton(provider: provider)
            }
        case .loaded(let usage), .failed(_, .some(let usage)):
            if usage.windows.isEmpty {
                Text("Aucune limite communiquée pour ce compte.").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
            ForEach(usage.windows) { window in
                UsageWindowRow(window: window, now: now)
            }
            if let spend = usage.spend {
                UsageSpendRow(spend: spend)
            }
        case .failed(_, nil):
            EmptyView()
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.l) {
                content
                if let error = state.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Typography.caption).foregroundStyle(Palette.warning)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
        } label: {
            HStack(spacing: Spacing.s) {
                UsageProviderLogo(provider: provider, size: IconSize.s)
                Text(provider.title).font(Typography.headline)
                if let plan = state.usage?.plan {
                    Text(plan).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}
