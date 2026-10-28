import SwiftUI

struct SidebarAppearancePicker: View {
    @Binding var appearance: SidebarAppearance
    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Icône").font(.callout.weight(.medium))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(SidebarSymbol.allCases) { symbol in
                        Button { appearance.symbol = symbol } label: {
                            SymbolCell(symbol: symbol, color: appearance.color, isSelected: appearance.displaySymbol == symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.displaySymbol == symbol ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Couleur").font(.callout.weight(.medium))
                HStack(spacing: 4) {
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
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? color : Color.secondary)
            .frame(width: 30, height: 30)
            .background(isSelected ? color.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isSelected { RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.6)) }
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
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: 18, height: 18)
        .padding(3)
        .overlay {
            if isSelected { Circle().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5) }
        }
        .contentShape(Circle())
    }
}
