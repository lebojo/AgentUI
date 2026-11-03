import SwiftUI

struct TerminalThemeCard: View {
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
