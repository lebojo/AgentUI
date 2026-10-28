import SwiftUI

struct SidebarAppearancePicker: View {
    @Binding var appearance: SidebarAppearance
    private let columns = Array(repeating: GridItem(.fixed(IconSize.xl), spacing: Spacing.s), count: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Icône").font(Typography.label)
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.s) {
                    ForEach(SidebarSymbol.allCases) { symbol in
                        Button { appearance.symbol = symbol } label: {
                            SymbolCell(symbol: symbol, color: appearance.color, isSelected: appearance.displaySymbol == symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.displaySymbol == symbol ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Couleur").font(Typography.label)
                HStack(spacing: Spacing.xs) {
                    Button { appearance.tint = nil } label: {
                        TintSwatch(color: appearance.kind.defaultColor, isAutomatic: true, isSelected: appearance.tint == nil)
                    }
                    .buttonStyle(.plain)
                    .help("Automatique")
                    .accessibilityLabel("Automatique")
                    .accessibilityAddTraits(appearance.tint == nil ? .isSelected : [])
                    ForEach(SidebarTint.allCases) { tint in
                        Button { appearance.tint = tint } label: {
                            TintSwatch(color: tint.color, isAutomatic: false, isSelected: appearance.tint == tint)
                        }
                        .buttonStyle(.plain)
                        .help(tint.title)
                        .accessibilityLabel(tint.title)
                        .accessibilityAddTraits(appearance.tint == tint ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct SymbolCell: View {
    let symbol: SidebarSymbol
    let color: Color
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol.systemName)
            .font(Typography.xl)
            .foregroundStyle(isSelected ? color : Palette.textSecondary)
            .frame(width: IconSize.xl, height: IconSize.xl)
            .background(isSelected ? color.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.m))
            .overlay {
                if isSelected { RoundedRectangle(cornerRadius: Radius.m).strokeBorder(color.opacity(0.6)) }
            }
            .contentShape(Rectangle())
    }
}

private struct TintSwatch: View {
    let color: Color
    let isAutomatic: Bool
    let isSelected: Bool

    var body: some View {
        Group {
            if isAutomatic {
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: Stroke.regular, dash: [3, 2]))
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: IconSize.m, height: IconSize.m)
        .padding(Spacing.xxs)
        .overlay {
            if isSelected { Circle().strokeBorder(Palette.textPrimary.opacity(0.55), lineWidth: Stroke.thin) }
        }
        .contentShape(Circle())
    }
}
