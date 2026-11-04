import SwiftUI

struct PromptSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            PromptEditorSection(
                prompt: $settings.prompts.commit,
                title: "Generate Commits",
                footer: "Sent to the default agent by “Generate Commits with AI” in the Git inspector.",
                defaultPrompt: AgentPrompts.defaultCommit
            )
            PromptEditorSection(
                prompt: $settings.prompts.changeRequest,
                title: "Create a Pull Request",
                footer: "Sent to the default agent by “Ask the Agent to Create the PR” (“the MR” on GitLab) in the Git inspector.",
                defaultPrompt: AgentPrompts.defaultChangeRequest
            )
        }
        .formStyle(.grouped)
    }
}
