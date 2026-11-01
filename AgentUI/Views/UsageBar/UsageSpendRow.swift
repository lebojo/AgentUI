import SwiftUI

struct UsageSpendRow: View {
    let spend: UsageSpend

    private var amounts: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: spend.currency)
        return String(localized: "\(spend.spent.formatted(style)) of \(spend.limit.formatted(style))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra Usage").font(Typography.label)
                Spacer()
                Text(spend.isEnabled ? amounts : String(localized: "Disabled"))
                    .font(Typography.body).monospacedDigit()
                    .foregroundStyle(spend.isEnabled ? Palette.textPrimary : Palette.textSecondary)
            }
            if spend.isEnabled, spend.limit > 0 {
                let percent = spend.spent / spend.limit * 100
                UsageGauge(fraction: min(1, percent / 100), level: UsageLevel(usedPercent: percent))
            }
            Text("Credits billed beyond your plan limits, each month.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
