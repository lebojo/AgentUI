import SwiftUI

struct FloatingTerminalTab: View {
    @Environment(FloatingTerminalStore.self) private var floating

    @State private var isHovered = false

    let tab: FloatingTerminal.Tab
    let title: String
    let directory: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: tab.layout.isSplit ? "rectangle.split.2x1" : "terminal")
                .font(Typography.xs)
                .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
            Text(title).lineLimit(1).truncationMode(.middle)
            Button { floating.close(tab) } label: { Image(systemName: "xmark").font(Typography.xxs.weight(.semibold)) }
                .buttonStyle(.borderless)
                .opacity(isHovered || isSelected ? 1 : 0)
                .help("Close Tab")
                .accessibilityLabel("Close tab \(title)")
        }
        .font(Typography.s)
        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: Dimension.FloatingTerminal.tabMaxWidth)
        .background(isSelected ? Palette.fill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Radius.m))
        .onTapGesture { floating.select(tab) }
        .onHover { isHovered = $0 }
        .help(directory)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { floating.select(tab) }
    }
}
