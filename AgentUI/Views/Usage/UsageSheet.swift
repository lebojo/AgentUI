import SwiftUI

struct UsageSheet: View {
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("Usage des agents").font(Typography.title)
                    Spacer()
                    if usage.isRefreshing { ProgressView().controlSize(.small) }
                    Button { Task { await usage.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(usage.isRefreshing)
                        .help("Actualiser")
                        .accessibilityLabel("Actualiser l’usage")
                }
                ForEach(UsageProvider.allCases) { provider in
                    UsageProviderSection(provider: provider, state: usage.state(for: provider), now: context.date)
                }
                HStack {
                    if let lastRefresh = usage.lastRefresh {
                        Text("Mis à jour \(lastRefresh.formatted(.relative(presentation: .named)))")
                            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xxl)
            .frame(width: Dimension.Sheet.width)
        }
    }
}

private struct UsageProviderSection: View {
    let provider: UsageProvider
    let state: UsageState
    let now: Date

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
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title).font(Typography.label)
                Spacer()
                Text("\(window.percentText) utilisés")
                    .font(Typography.body).monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Palette.textPrimary : window.level.tint)
            }
            UsageGauge(fraction: window.fraction, level: window.level)
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.detail)
                Spacer()
                if let countdown = window.resetText(from: now), let date = window.resetDateText(from: now) {
                    Text("Réinitialisation dans \(countdown) (\(date))").monospacedDigit()
                }
            }
            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UsageSpendRow: View {
    let spend: UsageSpend

    private var amounts: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: spend.currency)
        return "\(spend.spent.formatted(style)) sur \(spend.limit.formatted(style))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage supplémentaire").font(Typography.label)
                Spacer()
                Text(spend.isEnabled ? amounts : "Désactivé")
                    .font(Typography.body).monospacedDigit()
                    .foregroundStyle(spend.isEnabled ? Palette.textPrimary : Palette.textSecondary)
            }
            if spend.isEnabled, spend.limit > 0 {
                let percent = spend.spent / spend.limit * 100
                UsageGauge(fraction: min(1, percent / 100), level: UsageLevel(usedPercent: percent))
            }
            Text("Crédits facturés au-delà des limites du forfait, chaque mois.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
