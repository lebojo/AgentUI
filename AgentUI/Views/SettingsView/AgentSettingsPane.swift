import SwiftUI

struct AgentSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Default Agent", selection: $settings.agentLaunch.agent) {
                    ForEach(ConversationAgent.allCases) { agent in
                        Text(agent.title).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Launch the Agent Automatically") {
                Toggle(isOn: $settings.agentLaunch.onNewWorktree) {
                    Text("In a new worktree")
                    Text("The worktree’s first terminal starts directly in the agent.")
                }
                Toggle(isOn: $settings.agentLaunch.onNewTerminal) {
                    Text("In a new terminal")
                    Text("⌘T and the “New Terminal” buttons open the agent instead of a shell.")
                }
            }
            Section {
                Toggle(isOn: $settings.agentLaunch.skipsPermissions) {
                    Text("Without asking for permission")
                    Text(settings.agentLaunch.agent.permissionBypassFlag).font(Typography.captionMono)
                }
            } footer: {
                Text("The agent runs commands and edits files without confirmation. Keep this for isolated worktrees.")
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
            Section {
                LabeledContent("Launch Command") {
                    Text(settings.agentLaunch.previewCommand).font(Typography.code).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
