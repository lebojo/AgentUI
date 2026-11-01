import SwiftUI

struct TerminalPaletteEditor: View {
    @Binding var appearance: TerminalAppearance

    var body: some View {
        Group {
            ColorPicker("Fond", selection: color(\.background), supportsOpacity: false)
            ColorPicker("Texte", selection: color(\.foreground), supportsOpacity: false)
            ColorPicker("Curseur", selection: color(\.cursor), supportsOpacity: false)
            ColorPicker("Sélection", selection: color(\.selection), supportsOpacity: false)
            LabeledContent("Couleurs ANSI") { ansiRow(0..<8) }
            LabeledContent("Couleurs ANSI vives") { ansiRow(8..<16) }
        }
        .disabled(!appearance.isEditable)
    }

    private func ansiRow(_ indices: Range<Int>) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(indices, id: \.self) { index in
                ColorPicker("Couleur ANSI \(index)", selection: color(\.ansi[index]), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func color(_ keyPath: WritableKeyPath<TerminalPalette, TerminalColor>) -> Binding<Color> {
        Binding {
            appearance.palette?[keyPath: keyPath].color ?? .clear
        } set: { newValue in
            appearance.setColor(TerminalColor(newValue), at: keyPath)
        }
    }
}
