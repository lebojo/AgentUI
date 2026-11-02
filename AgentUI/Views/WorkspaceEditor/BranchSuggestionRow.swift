import SwiftUI

struct BranchSuggestionRow: View {
    let suggestion: BranchSuggestion

    var body: some View {
        Label {
            HStack(spacing: Spacing.s) {
                Text(suggestion.name)
                if let remote = suggestion.remote {
                    Text(remote).foregroundStyle(Palette.textSecondary)
                }
            }
        } icon: {
            Image(systemName: suggestion.remote == nil ? "arrow.triangle.branch" : "cloud")
        }
    }
}
