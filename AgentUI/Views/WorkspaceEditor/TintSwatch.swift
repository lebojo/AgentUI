import SwiftUI

struct TintSwatch: View {
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
