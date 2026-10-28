import SwiftUI
import AppKit

@main enum AgentUIEntry {
    static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        if executable == "agentui" || CommandLine.arguments.dropFirst().first == "--cli" {
            let arguments = Array(CommandLine.arguments.dropFirst(executable == "agentui" ? 1 : 2))
            exit(AgentCLI.run(arguments: arguments))
        }
        AgentUIApplication.main()
    }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var store: WorkspaceStore?
    var bridge: AgentBridge?
    var closeCommand: CloseTerminalCommand?

    private var finishingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !finishingTermination else { return .terminateLater }
        guard let store else { return .terminateNow }
        if store.sessions.runningCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Quitter AgentUI ?"
            alert.informativeText = "Les terminaux et leurs processus seront arrêtés. L’organisation de tes projets sera conservée."
            alert.addButton(withTitle: "Quitter")
            alert.addButton(withTitle: "Annuler")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        guard store.hasUnsavedChanges else { return .terminateNow }
        finishingTermination = true
        Task { @MainActor in
            do {
                repeat { try await store.flushPersistence() } while store.hasUnsavedChanges
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                finishingTermination = false
                store.errorMessage = "La fermeture a été annulée pour conserver les modifications non sauvegardées. \(error.localizedDescription)"
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        CommandRunner.cancelAll()
        store?.sessions.stopAll()
        bridge?.stop()
    }
}

struct AgentUIApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @State private var store = WorkspaceStore()

    var body: some Scene {
        Window("AgentUI", id: "workspace") {
            ContentView(store: store)
                .onAppear {
                    delegate.store = store
                    if delegate.closeCommand == nil { delegate.closeCommand = CloseTerminalCommand(store: store) }
                    if delegate.bridge == nil {
                        do { delegate.bridge = try AgentBridge(store: store) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ajouter un projet…") { store.chooseProjects() }.keyboardShortcut("o").disabled(store.isReadOnly || store.isImporting)
                Button("Importer un dossier…") { store.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(store.isReadOnly || store.isImporting)
            }
            CommandGroup(replacing: .help) {
                Button("Commandes pour les agents") {
                    let alert = NSAlert()
                    alert.messageText = "Commander AgentUI depuis un terminal"
                    alert.informativeText = AgentCLI.help
                    alert.runModal()
                }
            }
        }
    }
}
