import SwiftUI

struct BranchSuggestions: ViewModifier {
    let suggestions: [BranchSuggestion]

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.textInputSuggestions(suggestions) { suggestion in
                BranchSuggestionRow(suggestion: suggestion)
                    .textInputCompletion(suggestion.name)
            }
        } else {
            content
        }
    }
}
