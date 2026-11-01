import SwiftUI

struct UsageSpendRow: View {
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
