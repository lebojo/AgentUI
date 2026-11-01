import SwiftUI

struct DiffLineNumber: View {
    let number: Int?
    let digits: Int

    var body: some View {
        Text(String(repeating: "0", count: digits)).hidden()
            .overlay(alignment: .trailing) { Text(number.map(String.init) ?? "").foregroundStyle(Palette.textTertiary) }
            .font(Typography.code)
            .padding(.leading, Spacing.s)
            .textSelection(.disabled)
            .accessibilityHidden(true)
    }
}
