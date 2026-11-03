import SwiftUI

struct SymbolCell: View {
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
