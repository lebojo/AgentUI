import SwiftUI

struct MobileTerminalSettingsSection: View {
    @AppStorage(TerminalAppearance.mobileFontSizeKey) private var fontSize = TerminalAppearance.defaultFontSize

    var body: some View {
        Section {
            Stepper(value: $fontSize, in: TerminalAppearance.fontSizes) {
                LabeledContent("Text Size") { Text("\(Int(fontSize)) pt") }
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text("While you view a terminal, the Mac resizes it to fit this screen. It returns to its own size when you leave or use it on the Mac.")
        }
    }
}
