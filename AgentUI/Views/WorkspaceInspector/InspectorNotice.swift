import SwiftUI

struct InspectorNotice: View {
    let title: LocalizedStringKey
    let message: String
    var symbol = "exclamationmark.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(title, systemImage: symbol).font(Typography.label)
            Text(message).font(Typography.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
        }
    }
}
