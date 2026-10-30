import SwiftUI

/// Native text keeps selection and accessibility. Fenced code gets its own
/// horizontal viewport instead of imposing terminal-width wrapping on prose.
struct SessionMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { index, block in
                if index.isMultiple(of: 2) {
                    Text(.init(block)).font(Typography.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let code = block.firstIndex(of: "\n").map { String(block[block.index(after: $0)...]) } ?? block
                    ScrollView(.horizontal) {
                        Text(verbatim: code.trimmingCharacters(in: .newlines)).font(Typography.code).textSelection(.enabled)
                            .padding(Spacing.m)
                    }.background(Palette.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.s))
                }
            }
        }
    }
}
