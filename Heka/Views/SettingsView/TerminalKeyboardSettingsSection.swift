import SwiftUI

struct TerminalKeyboardSettingsSection: View {
    @AppStorage(TerminalKeyRoute.metaKeySetting) private var optionAsMetaKey = false

    var body: some View {
        Section {
            Toggle("Use Option as Meta key", isOn: $optionAsMetaKey)
        } header: {
            Text("Keyboard")
        } footer: {
            Text("When off, Option types characters such as @, [ or ~. Option with the arrow keys, Delete or Return always acts as Meta.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}
