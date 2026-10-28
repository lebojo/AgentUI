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

private struct TerminalThemeCard: View {
    let appearance: TerminalAppearance
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("❯ ").foregroundStyle(appearance.ansi[2]) + Text("ls").foregroundStyle(appearance.foreground)
                HStack(spacing: Spacing.xs) {
                    ForEach(1..<7) { index in
                        Circle().fill(appearance.ansi[index])
                            .frame(width: Dimension.Settings.swatchSize, height: Dimension.Settings.swatchSize)
                    }
                }
            }
            .font(Typography.code)
            .frame(maxWidth: .infinity, minHeight: Dimension.Settings.themeSampleHeight, alignment: .leading)
            .padding(.horizontal, Spacing.m)
            .background(appearance.background, in: RoundedRectangle(cornerRadius: Radius.m))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.m)
                    .strokeBorder(isSelected ? Palette.accent : Palette.fill, lineWidth: isSelected ? Stroke.regular : 1)
            }
            Text(appearance.theme.title)
                .font(Typography.s)
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

private extension TerminalAppearance {
    func previewing(_ theme: TerminalTheme) -> TerminalAppearance {
        var preview = self
        preview.theme = theme
        return preview
    }
}
