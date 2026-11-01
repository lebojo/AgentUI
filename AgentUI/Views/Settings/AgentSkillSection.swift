import SwiftUI

struct AgentSkillSection: View {
    @State private var status = AgentSkillStatus.notInstalled
    @State private var errorMessage: String?

    private let installer = AgentSkillInstaller.bundled

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    if status.isPresent {
                        Button("Désinstaller", role: .destructive) { perform { try $0.uninstall() } }
                    }
                    if status.needsInstall {
                        Button(status.actionTitle) { perform { try $0.install() } }
                    }
                }
                .disabled(installer == nil)
            } label: {
                Text("Skill agentui")
                Text(status.title)
            }
            if let errorMessage {
                Text(errorMessage).font(Typography.caption).foregroundStyle(Palette.danger)
            }
        } header: {
            Text("Commande agentui")
        } footer: {
            Text("Apprend à Claude, Codex, Copilot et OpenCode quand et comment piloter AgentUI depuis un terminal : agents en parallèle dans un worktree, relecture, serveur de dev, nettoyage. Installé dans ~/.agents/skills/agentui, avec un lien dans ~/.claude/skills. Aussi installable avec npx skills add LeBojo/AgentUI.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard let installer else {
            errorMessage = "Le skill est introuvable dans l’application."
            return
        }
        status = installer.status
    }

    private func perform(_ action: (AgentSkillInstaller) throws -> Void) {
        guard let installer else { return }
        do {
            try action(installer)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        status = installer.status
    }
}
