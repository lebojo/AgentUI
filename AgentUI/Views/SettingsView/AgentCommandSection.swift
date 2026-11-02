import SwiftUI

struct AgentCommandSection: View {
    var body: some View {
        Section {
            InstallationRow(title: String(localized: "Command in PATH")) { try await CommandLineInstaller.load() }
            InstallationRow(title: String(localized: "Skill for Agents")) { try await AgentSkillInstaller.load() }
        } header: {
            Text("agentui Command")
        } footer: {
            Text("The command is linked in ~/.local/bin; add it to your PATH if it isn’t there. Outside an AgentUI terminal, it acts on the project of the current folder. The skill teaches Claude, Codex, Copilot and OpenCode when to use it; it can also be installed with npx skills add LeBojo/AgentUI.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}
