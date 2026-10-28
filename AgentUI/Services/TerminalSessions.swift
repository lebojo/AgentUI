import AppKit
import SwiftUI
import SwiftTerm
import Observation

@MainActor @Observable final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    private(set) var hasExited = false
    private(set) var exitCode: Int32?
    private(set) var title = ""
    let path: String
    let identity = UUID()
    private(set) var currentDirectory: String
    private(set) var branch: GitBranch?

    init(context: TerminalContext, command: [String], environment: [String: String]) {
        path = context.worktree.path
        currentDirectory = context.worktree.path
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        view.processDelegate = self
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            hasExited = true
            view.feed(text: "Le dossier n’est plus accessible :\r\n\(path)\r\n")
            return
        }
        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "AgentUI"
        env["AGENTUI_PROJECT_ID"] = context.project.id.uuidString
        env["AGENTUI_WORKTREE_ID"] = context.worktree.id.uuidString
        env["AGENTUI_TERMINAL_ID"] = context.terminal.id.uuidString
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        let configuredShell = env["SHELL"] ?? "/bin/zsh"
        let shell = FileManager.default.isExecutableFile(atPath: configuredShell) ? configuredShell : "/bin/zsh"
        let args = command.isEmpty ? ["-l"] : ["-l", "-c", "exec \"$@\"", "agentui"] + command
        view.startProcess(executable: shell, args: args, environment: env.map { "\($0.key)=\($0.value)" }, currentDirectory: path)
        if !view.process.running {
            hasExited = true
            view.feed(text: "Impossible de démarrer le terminal.\r\n")
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { self.title = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasExited = true
        self.exitCode = exitCode
    }
    func updateRepository(directory: String, branch: GitBranch?) {
        if currentDirectory != directory { currentDirectory = directory }
        if self.branch != branch { self.branch = branch }
    }

    func stop() {
        guard view.process.running else { return }
        let pid = view.process.shellPid
        if pid > 0 { kill(-pid, SIGHUP) }
        view.terminate()
    }
}

@MainActor @Observable final class TerminalSessions {
    private var entries: [UUID: TerminalSession] = [:]
    var environment: [String: String] = [:]
    private(set) var branchesByPath: [String: GitBranch] = [:]
    @ObservationIgnored private var refreshingRepositories = false

    func branch(for terminalID: UUID, initialPath: String) -> GitBranch? {
        if let session = entries[terminalID] { return session.branch }
        return branchesByPath[initialPath]
    }

    func refreshRepositories(worktreePaths: [String]) async {
        guard !refreshingRepositories else { return }
        refreshingRepositories = true
        defer { refreshingRepositories = false }
        let locations = entries.map { id, session in
            (id: id, identity: session.identity, pid: session.hasExited ? Int32(0) : session.view.process.shellPid,
             fallback: session.currentDirectory)
        }
        let result = await Task.detached(priority: .utility) {
            var cache: [String: GitBranch?] = [:]
            func branch(at path: String) -> GitBranch? {
                if let cached = cache[path] { return cached }
                let value = GitRepository.containing(path)?.branch
                cache[path] = .some(value)
                return value
            }
            var branches: [String: GitBranch] = [:]
            for path in Set(worktreePaths) { branches[path] = branch(at: path) }
            let sessions = locations.map { location in
                let directory = TerminalProcessDirectory.read(pid: location.pid) ?? location.fallback
                return (id: location.id, identity: location.identity, directory: directory, branch: branch(at: directory))
            }
            return (branches: branches, sessions: sessions)
        }.value
        guard !Task.isCancelled else { return }
        if branchesByPath != result.branches { branchesByPath = result.branches }
        for value in result.sessions {
            guard let session = entries[value.id], session.identity == value.identity else { continue }
            session.updateRepository(directory: value.directory, branch: value.branch)
        }
    }

    var runningCount: Int { entries.values.filter { !$0.hasExited }.count }

    func session(_ id: UUID) -> TerminalSession? { entries[id] }
    @discardableResult func start(_ context: TerminalContext, command: [String] = []) -> TerminalSession {
        if let session = entries[context.terminal.id] { return session }
        let session = TerminalSession(context: context, command: command, environment: environment)
        entries[context.terminal.id] = session
        return session
    }
    func close(_ id: UUID) { entries.removeValue(forKey: id)?.stop() }
    func stopAll() {
        for session in entries.values { session.stop() }
        entries.removeAll()
    }
}

struct NativeTerminalView: NSViewRepresentable {
    final class Coordinator {
        var appliedAppearance: TerminalAppearance?
        var appliedColorScheme: ColorScheme?
    }

    let session: TerminalSession
    let appearance: TerminalAppearance

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.setAccessibilityLabel("Terminal interactif")
        let terminal = session.view
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            terminal.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            terminal.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8)
        ])
        applyAppearance(context: context)
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) { applyAppearance(context: context) }

    private func applyAppearance(context: Context) {
        let colorScheme = context.environment.colorScheme
        guard context.coordinator.appliedAppearance != appearance || context.coordinator.appliedColorScheme != colorScheme else { return }
        context.coordinator.appliedAppearance = appearance
        context.coordinator.appliedColorScheme = colorScheme
        session.view.apply(appearance)
    }
}
