import SwiftUI

struct TerminalThemeGrid: View {
    @Binding var appearance: TerminalAppearance

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Dimension.Settings.themeCardMinWidth), spacing: Spacing.m)], spacing: Spacing.m) {
            ForEach(TerminalTheme.allCases) { theme in
                Button { appearance.select(theme) } label: {
                    TerminalThemeCard(appearance: appearance.previewing(theme), isSelected: appearance.theme == theme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
