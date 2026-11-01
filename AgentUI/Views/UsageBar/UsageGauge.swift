import SwiftUI

struct UsageGauge: View {
    let fraction: Double
    let level: UsageLevel

    var body: some View {
        ProgressView(value: fraction)
            .progressViewStyle(.linear)
            .tint(level.tint)
            .accessibilityHidden(true)
    }
}

extension UsageLevel {
    var tint: Color {
        switch self {
        case .comfortable: Palette.accent
        case .warning: Palette.warning
        case .critical: Palette.danger
        }
    }
}

extension UsageWindow {
    var percentText: String { "\(Int(usedPercent.rounded())) %" }

    func resetText(from now: Date) -> String? {
        resetsAt.map { UsageCountdown.text(until: $0, from: now) }
    }

    func resetDateText(from now: Date) -> String? {
        guard let resetsAt else { return nil }
        let sameDay = Calendar.current.isDate(resetsAt, inSameDayAs: now)
        return resetsAt.formatted(sameDay ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).day().hour().minute())
    }
}
