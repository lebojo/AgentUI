import SwiftUI

struct WorktreeLaunchPicker: View {
    @Binding var launch: AgentLaunch

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle("Start with", isOn: $launch.onNewWorktree)
            Picker("Agent", selection: $launch.agent) {
                ForEach(ConversationAgent.allCases) { agent in
                    Text(agent.title).tag(agent)
                }
            }
            .labelsHidden().fixedSize()
            .disabled(!launch.onNewWorktree)
        }
    }
}
