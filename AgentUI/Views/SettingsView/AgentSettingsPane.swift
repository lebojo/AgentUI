import SwiftUI

struct AgentSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Agent par défaut", selection: $settings.agentLaunch.agent) {
                    ForEach(ConversationAgent.allCases) { agent in
                        Text(agent.title).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Lancer l’agent automatiquement") {
                Toggle(isOn: $settings.agentLaunch.onNewWorktree) {
                    Text("Dans un nouveau worktree")
                    Text("Le premier terminal du worktree démarre directement sur l’agent.")
                }
                Toggle(isOn: $settings.agentLaunch.onNewTerminal) {
                    Text("Dans un nouveau terminal")
                    Text("⌘T et les boutons « Nouveau terminal » ouvrent l’agent au lieu d’un shell.")
                }
            }
            Section {
                Toggle(isOn: $settings.agentLaunch.skipsPermissions) {
                    Text("Sans demander d’autorisation")
                    Text(settings.agentLaunch.agent.permissionBypassFlag).font(Typography.captionMono)
                }
            } footer: {
                Text("L’agent exécute des commandes et modifie des fichiers sans confirmation. À réserver aux worktrees isolés.")
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
            Section {
                LabeledContent("Commande lancée") {
                    Text(settings.agentLaunch.previewCommand).font(Typography.code).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
