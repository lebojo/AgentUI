import SwiftUI

struct SplitDiffRow: View {
    let row: GitDiffRow
    let digits: Int

    var body: some View {
        switch row.content {
        case .banner(let line):
            DiffBanner(line: line)
        case .pair(let old, let new):
            HStack(spacing: 0) {
                SplitDiffSide(line: old, number: old?.oldNumber, digits: digits)
                Divider()
                SplitDiffSide(line: new, number: new?.newNumber, digits: digits)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SplitDiffSide: View {
    let line: GitDiffLine?
    let number: Int?
    let digits: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let line {
                DiffLineNumber(number: number, digits: digits)
                DiffCode(line: line)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(line?.kind.background ?? Palette.fill)
    }
}
