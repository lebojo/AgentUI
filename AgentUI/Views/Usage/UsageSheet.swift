import SwiftUI

struct UsageSheet: View {
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Usage des agents").font(.title3.weight(.semibold))
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
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
    }
}

private struct UsageProviderSection: View {
    let provider: UsageProvider
    let state: UsageState
    let now: Date

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                content
                if let error = state.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            HStack(spacing: 6) {
                UsageProviderLogo(provider: provider, size: 15)
                Text(provider.title).font(.headline)
                if let plan = state.usage?.plan {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Chargement…").font(.callout).foregroundStyle(.secondary)
            }
        case .signedOut:
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Non connecté").font(.callout.weight(.medium))
                    Text(provider.signInHint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                UsageSignInButton(provider: provider)
            }
        case .loaded(let usage), .failed(_, .some(let usage)):
            if usage.windows.isEmpty {
                Text("Aucune limite communiquée pour ce compte.").font(.callout).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title).font(.callout.weight(.medium))
                Spacer()
                Text("\(window.percentText) utilisés")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Color.primary : window.level.tint)
            }
            UsageGauge(fraction: window.fraction, level: window.level)
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.detail)
                Spacer()
                if let countdown = window.resetText(from: now), let date = window.resetDateText(from: now) {
                    Text("Réinitialisation dans \(countdown) (\(date))").monospacedDigit()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage supplémentaire").font(.callout.weight(.medium))
                Spacer()
                Text(spend.isEnabled ? amounts : "Désactivé")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(spend.isEnabled ? Color.primary : Color.secondary)
            }
            if spend.isEnabled, spend.limit > 0 {
                let percent = spend.spent / spend.limit * 100
                UsageGauge(fraction: min(1, percent / 100), level: UsageLevel(usedPercent: percent))
            }
            Text("Crédits facturés au-delà des limites du forfait, chaque mois.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
