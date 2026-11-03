import SwiftUI
import AppKit

struct WorktreeFolderSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            LabeledContent("Creation Folder") {
                Text(settings.creationWorktreesDirectory.path.abbreviatingHome).font(Typography.code).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Reset") { settings.worktreesDirectory = WorkspaceDisk.defaultWorktreesDirectory }
                    .disabled(settings.usesDefaultWorktreesDirectory)
                Button("Choose…") {
                    chooseFolder(message: String(localized: "Choose the folder where Heka creates new worktrees.")) { settings.worktreesDirectory = $0 }
                }
            }
        } header: {
            Text("Worktrees")
        } footer: {
            Text("New worktrees are created in this folder. Existing worktrees stay where they are.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        Section {
            ForEach(settings.scannedWorktreesDirectories, id: \.path) { directory in
                HStack {
                    Text(directory.path.abbreviatingHome).font(Typography.code).textSelection(.enabled)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { settings.scannedWorktreesDirectories.removeAll { $0.path == directory.path } }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Stop scanning this folder")
                }
            }
            HStack {
                Spacer()
                Button("Add Folder…") {
                    chooseFolder(message: String(localized: "Choose a folder whose worktrees Heka shows in the sidebar.")) { settings.addScannedWorktreesDirectory($0) }
                }
            }
        } header: {
            Text("Other Worktree Folders")
        } footer: {
            Text("The worktrees in these folders also appear in the sidebar. Heka never creates worktrees there.")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
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
