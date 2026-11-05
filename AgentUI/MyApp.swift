import SwiftUI
import AppKit

@main enum AgentUIEntry {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            exit(AgentCLI.run(arguments: Array(CommandLine.arguments.dropFirst(2))))
        }
        if CommandLine.arguments.first.map({ URL(fileURLWithPath: $0).lastPathComponent }) == CommandLineInstaller.commandName {
            exit(AgentCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
        }
        AgentUIApplication.main()
    }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var store: WorkspaceStore?
    var floating: FloatingTerminalStore?
    var bridge: AgentBridge?
    var closeCommand: CloseTerminalCommand?
    var host: LocalHost?

    private var finishingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !finishingTermination else { return .terminateLater }
        guard let store else { return .terminateNow }
        if store.sessions.runningCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit AgentUI?")
            alert.informativeText = String(localized: "Terminals and their processes will be stopped. Your project organization will be kept and agent sessions will resume the next time you open AgentUI.")
            alert.addButton(withTitle: String(localized: "Quit"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        guard store.sessions.runningCount > 0 || store.hasUnsavedChanges else { return .terminateNow }
        finishingTermination = true
        Task { @MainActor in
            if store.sessions.runningCount > 0 {
                await store.sessions.refreshAgents()
                store.recordAgentSessions()
            }
            do {
                repeat { try await store.flushPersistence() } while store.hasUnsavedChanges
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                finishingTermination = false
                store.errorMessage = String(localized: "Quitting was cancelled to keep unsaved changes. \(error.localizedDescription)")
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        CommandRunner.cancelAll()
        floating?.persist()
        store?.sessions.stopAll()
        bridge?.stop()
        host?.stop()
    }
}

struct AgentUIApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @State private var store: WorkspaceStore
    @State private var floating: FloatingTerminalStore
    @State private var usage = UsageStore(providers: [])
    @State private var settings = SettingsStore()
    @State private var visibility = AppVisibility()
    @State private var host = LocalHost()
    @State private var installedAgents = InstalledAgents()
    @State private var gitActionQueues = GitActionQueues()

    init() {
        let store = WorkspaceStore()
        _store = State(initialValue: store)
        _floating = State(initialValue: FloatingTerminalStore(sessions: store.sessions))
    }

    var body: some Scene {
        Window("AgentUI", id: "workspace") {
            ContentView(store: store, gitActionQueues: gitActionQueues)
                .environment(store)
                .environment(floating)
                .environment(usage)
                .environment(settings)
                .environment(visibility)
                .environment(installedAgents)
                .task(id: visibility.isVisible) { if visibility.isVisible { await installedAgents.refresh() } }
                .task(id: installedAgents.agents) { await usage.setInstalled(installedAgents.agents) }
                .onAppear {
                    delegate.store = store
                    delegate.floating = floating
                    delegate.host = host
                    host.configure(store: store, settings: settings, installedAgents: installedAgents)
                    if delegate.closeCommand == nil { delegate.closeCommand = CloseTerminalCommand(store: store, floating: floating) }
                    if delegate.bridge == nil {
                        do { delegate.bridge = try AgentBridge(store: store) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    store.restoreSessions()
                }
        }
        .defaultSize(width: Dimension.Window.defaultWidth, height: Dimension.Window.defaultHeight)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Project…") { store.chooseProjects() }.keyboardShortcut("o").disabled(store.isReadOnly || store.isImporting)
                Button("Import Folder…") { store.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(store.isReadOnly || store.isImporting)
            }
            FloatingTerminalCommands(floating: floating)
            CommandGroup(replacing: .help) {
                Button("Agent Commands") {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Control AgentUI from a Terminal")
                    alert.informativeText = AgentCLI.help
                    alert.runModal()
                }
            }
        }
        Settings {
            SettingsView()
                .environment(settings)
                .environment(host)
        }
    }
}
