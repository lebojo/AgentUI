import SwiftUI

struct TerminalSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Thème") {
                TerminalPreview(appearance: settings.terminal)
                TerminalThemeGrid(appearance: $settings.terminal)
            }
            Section("Police") {
                Picker("Police", selection: $settings.terminal.fontFamily) {
                    Text("Système").tag("")
                    Divider()
                    ForEach(MonospacedFonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $settings.terminal.fontSize, in: TerminalAppearance.fontSizes) {
                    LabeledContent("Taille", value: "\(Int(settings.terminal.fontSize)) pt")
                }
            }
            Section("Curseur") {
                Picker("Forme", selection: $settings.terminal.cursorShape) {
                    ForEach(TerminalCursorShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Clignotant", isOn: $settings.terminal.cursorBlinks)
            }
            Section {
                TerminalPaletteEditor(appearance: $settings.terminal)
            } header: {
                Text("Couleurs")
            } footer: {
                if !settings.terminal.isEditable {
                    Text("Le thème Système suit le mode clair ou sombre de macOS. Choisis un autre thème pour modifier ses couleurs.")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Réinitialiser") { settings.terminal = TerminalAppearance() }
                        .disabled(settings.terminal == TerminalAppearance())
                }
            }
        }
        .formStyle(.grouped)
    }
}
