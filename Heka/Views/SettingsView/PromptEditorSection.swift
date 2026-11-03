import SwiftUI

struct PromptEditorSection: View {
    @Binding var prompt: String

    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let defaultPrompt: String

    var body: some View {
        Section {
            TextEditor(text: $prompt)
                .font(Typography.code)
                .frame(minHeight: Dimension.Settings.promptEditorHeight)
            Button("Restore Default") { prompt = defaultPrompt }
                .disabled(prompt == defaultPrompt)
        } header: {
            Text(title)
        } footer: {
            Text(footer).font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}
