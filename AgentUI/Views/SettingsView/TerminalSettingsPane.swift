import SwiftUI

struct TerminalSettingsPane: View {
    @AppStorage("sessionDisplayMode") private var displayMode: SessionDisplayMode = .terminal
    @AppStorage(TerminalKeyRoute.metaKeySetting) private var optionAsMetaKey = false

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            SessionDisplaySettingsSection(mode: $displayMode)
            Section("Theme") {
                TerminalPreview(appearance: settings.terminal)
                TerminalThemeGrid(appearance: $settings.terminal)
            }
            Section("Font") {
                Picker("Font", selection: $settings.terminal.fontFamily) {
                    Text("System").tag("")
                    Divider()
                    ForEach(MonospacedFonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $settings.terminal.fontSize, in: TerminalAppearance.fontSizes) {
                    LabeledContent("Size", value: "\(Int(settings.terminal.fontSize)) pt")
                }
            }
            Section("Cursor") {
                Picker("Shape", selection: $settings.terminal.cursorShape) {
                    ForEach(TerminalCursorShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Blinking", isOn: $settings.terminal.cursorBlinks)
            }
            Section {
                Toggle("Use Option as Meta key", isOn: $optionAsMetaKey)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("When off, Option types characters such as @, [ or ~. Option with the arrow keys, Delete or Return always acts as Meta.")
            }
            Section {
                TerminalPaletteEditor(appearance: $settings.terminal)
            } header: {
                Text("Colors")
            } footer: {
                if !settings.terminal.isEditable {
                    Text("The System theme follows macOS light or dark mode. Choose another theme to edit its colors.")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset") { settings.terminal = TerminalAppearance() }
                        .disabled(settings.terminal == TerminalAppearance())
                }
            }
        }
        .formStyle(.grouped)
    }
}
