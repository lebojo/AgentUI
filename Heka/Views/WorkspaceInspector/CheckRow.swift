import SwiftUI

struct CheckRow: View {
    let title: String
    let result: String
    let url: String?

    private var status: (symbol: String, color: Color, title: String) {
        switch result.uppercased() {
        case "SUCCESS": ("checkmark.circle.fill", Palette.success, String(localized: "Succeeded"))
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED": ("xmark.circle.fill", Palette.danger, String(localized: "Failed"))
        case "CANCELLED": ("slash.circle", Palette.textSecondary, String(localized: "Cancelled"))
        case "SKIPPED", "NEUTRAL": ("minus.circle", Palette.textSecondary, String(localized: "Skipped"))
        default: ("clock", Palette.warning, String(localized: "Pending / Running"))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: status.symbol).foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let url, let destination = URL(string: url) { Link(title, destination: destination) }
                else { Text(title) }
                Text(status.title).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }.font(Typography.body)
        }.padding(.vertical, Spacing.xxs)
    }
}
