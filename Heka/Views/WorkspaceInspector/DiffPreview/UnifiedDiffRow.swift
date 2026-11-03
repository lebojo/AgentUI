import SwiftUI

struct UnifiedDiffRow: View {
    let line: GitDiffLine
    let digits: Int

    var body: some View {
        if line.kind.isBanner {
            DiffBanner(line: line)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                DiffLineNumber(number: line.oldNumber, digits: digits)
                DiffLineNumber(number: line.newNumber, digits: digits)
                DiffCode(line: line)
            }.background(line.kind.background)
        }
    }
}
