import SwiftUI

struct InspectorNotice: View {
    let title: LocalizedStringResource
    let message: Text
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label { Text(title) } icon: { Image(systemName: symbol) }.font(Typography.label)
            message.font(Typography.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
        }
    }

    init(title: LocalizedStringResource, error: String, symbol: String = "exclamationmark.circle") {
        self.init(title: title, text: Text(error), symbol: symbol)
    }

    init(title: LocalizedStringResource, message: LocalizedStringResource, symbol: String = "exclamationmark.circle") {
        self.init(title: title, text: Text(message), symbol: symbol)
    }

    private init(title: LocalizedStringResource, text: Text, symbol: String) {
        self.title = title
        message = text
        self.symbol = symbol
    }
}
