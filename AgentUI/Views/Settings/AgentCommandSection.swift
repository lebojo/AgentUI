import SwiftUI

struct AgentCommandSection: View {
    var body: some View {
        Section {
            InstallationRow(title: "Commande dans le PATH") { try await CommandLineInstaller.load() }
            InstallationRow(title: "Skill pour les agents") { try await AgentSkillInstaller.load() }
        } header: {
            Text("Commande agentui")
        } footer: {
            Text("La commande est liée dans ~/.local/bin, à ajouter au PATH s’il n’y est pas. Hors d’un terminal AgentUI, elle agit sur le projet du dossier courant. Le skill apprend à Claude, Codex, Copilot et OpenCode quand l’utiliser ; il est aussi installable avec npx skills add LeBojo/AgentUI.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}
