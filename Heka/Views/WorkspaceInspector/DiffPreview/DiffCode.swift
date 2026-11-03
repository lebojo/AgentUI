import SwiftUI

struct DiffCode: View {
    let line: GitDiffLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.kind.marker).foregroundStyle(line.kind.markerColor)
                .frame(width: Dimension.DiffSheet.markerWidth)
                .textSelection(.disabled)
            Text("\(line.text)\(Text(line.endingSymbols).foregroundStyle(Palette.textTertiary))")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Typography.code)
        .padding(.leading, Spacing.xs)
        .padding(.vertical, Spacing.xxs / 2)
        .help(line.missingFinalNewline ? String(localized: "No newline at end of file") : "")
    }
}
