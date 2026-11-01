import SwiftUI

struct UsageBarRow: View {
    let provider: UsageProvider
    let state: UsageState
    let now: Date

    private var windows: [UsageWindow] {
        guard let usage = state.usage else { return [] }
        let preferred = [usage.session, usage.weekly].compactMap { $0 }
        return preferred.isEmpty ? Array(usage.windows.prefix(2)) : preferred
    }

    private var countdown: String? {
        state.usage?.headline?.resetText(from: now)
    }

    private var accessibilityText: String {
        let parts = windows.map { "\($0.kind.title) : \($0.percentText) utilisés" }
        let reset = countdown.map { ", réinitialisation dans \($0)" } ?? ""
        return "\(provider.title), " + parts.joined(separator: ", ") + reset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                UsageProviderLogo(provider: provider, size: IconSize.xs)
                Text(provider.title).fontWeight(.medium)
                if state.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                        .help(state.error ?? "")
                }
                Spacer(minLength: Spacing.xs)
                if let countdown {
                    Label(countdown, systemImage: "arrow.clockwise")
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.s)
            HStack(spacing: Spacing.m) {
                ForEach(windows) { window in
                    UsageCompactMeter(window: window)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
