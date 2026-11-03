import SwiftUI

struct UsageWindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title).font(Typography.label)
                Spacer()
                Text("\(window.percentText) used")
                    .font(Typography.body).monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Palette.textPrimary : window.level.tint)
            }
            UsageGauge(fraction: window.fraction, level: window.level)
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.detail)
                Spacer()
                if let countdown = window.resetText(from: now), let date = window.resetDateText(from: now) {
                    Text("Resets in \(countdown) (\(date))").monospacedDigit()
                }
            }
            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
