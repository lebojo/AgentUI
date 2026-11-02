import SwiftUI
import AppKit

struct WorktreeFolderSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            LabeledContent("Creation Folder") {
                Text(abbreviated(settings.creationWorktreesDirectory)).font(Typography.code).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Reset") { settings.worktreesDirectory = WorkspaceDisk.defaultWorktreesDirectory }
                    .disabled(settings.usesDefaultWorktreesDirectory)
                Button("Choose…") {
                    chooseFolder(message: String(localized: "Choose the folder where AgentUI creates new worktrees.")) { settings.worktreesDirectory = $0 }
                }
            }
        } header: {
            Text("Worktrees")
        } footer: {
            Text("New worktrees are created in this folder. Existing worktrees stay where they are.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder(message: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = String(localized: "Choose")
        panel.message = message
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in completion(url.standardizedFileURL) }
        }
    }
}
