import SwiftUI

struct UsageCompactMeter: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(window.kind.shortTitle).foregroundStyle(Palette.textSecondary)
            UsageGauge(fraction: window.fraction, level: window.level)
            Text(window.percentText)
                .monospacedDigit()
                .foregroundStyle(window.level == .comfortable ? Palette.textSecondary : window.level.tint)
                .frame(minWidth: Dimension.Usage.percentMinWidth, alignment: .trailing)
        }
        .font(Typography.xs)
    }
}
