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
