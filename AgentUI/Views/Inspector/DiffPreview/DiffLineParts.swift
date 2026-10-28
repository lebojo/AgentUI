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
        .help(line.missingFinalNewline ? "Pas de saut de ligne en fin de fichier" : "")
    }
}

struct DiffBanner: View {
    let line: GitDiffLine

    var body: some View {
        Text(line.text)
            .font(Typography.code).foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
            .background(line.kind.background)
    }
}
