import SwiftUI

struct TerminalPaletteEditor: View {
    @Binding var appearance: TerminalAppearance

    var body: some View {
        Group {
            ColorPicker("Background", selection: color(\.background), supportsOpacity: false)
            ColorPicker("Text", selection: color(\.foreground), supportsOpacity: false)
            ColorPicker("Cursor", selection: color(\.cursor), supportsOpacity: false)
            ColorPicker("Selection", selection: color(\.selection), supportsOpacity: false)
            LabeledContent("ANSI Colors") { ansiRow(0..<8) }
            LabeledContent("Bright ANSI Colors") { ansiRow(8..<16) }
        }
        .disabled(!appearance.isEditable)
    }

    private func ansiRow(_ indices: Range<Int>) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(indices, id: \.self) { index in
                ColorPicker("ANSI Color \(index)", selection: color(\.ansi[index]), supportsOpacity: false)
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
