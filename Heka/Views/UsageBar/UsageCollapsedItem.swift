import SwiftUI

struct UsageCollapsedItem: View {
    let provider: UsageProvider
    let state: UsageState

    private var window: UsageWindow? { state.usage?.headline }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            UsageProviderLogo(provider: provider, size: IconSize.xs)
            if let window {
                Text(window.percentText)
                    .monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Palette.textSecondary : window.level.tint)
            } else {
                Text("—").foregroundStyle(Palette.textSecondary)
            }
            if state.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    .help(state.error ?? "")
            }
        }
        .font(Typography.s.weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.map { "\(provider.title), " + String(localized: "\($0.kind.title): \($0.percentText) used") } ?? "\(provider.title), " + String(localized: "usage unavailable"))
    }
}
