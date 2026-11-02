import Foundation

enum SettingsTests {
    static func run() throws {
        var launch = AgentLaunch()
        try CoreTests.require(launch.command(on: .newTerminal).isEmpty && launch.command(on: .newWorktree).isEmpty, "Agents are not launched by default")
        launch.onNewWorktree = true
        try CoreTests.require(launch.command(on: .newWorktree) == ["claude"] && launch.command(on: .newTerminal).isEmpty, "Each trigger is independent")
        launch.skipsPermissions = true
        try CoreTests.require(launch.command(on: .newWorktree) == ["claude", "--dangerously-skip-permissions"], "Claude permission bypass flag")
        launch.agent = .codex
        launch.onNewTerminal = true
        try CoreTests.require(launch.command(on: .newTerminal) == ["codex", "--dangerously-bypass-approvals-and-sandbox"], "Codex permission bypass flag")
        let decodedLaunch = try JSONDecoder().decode(AgentLaunch.self, from: JSONEncoder().encode(launch))
        try CoreTests.require(decodedLaunch == launch, "Agent launch round-trips")
        print("PASS agent launch settings")

        let suite = "AgentUI.SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        try CoreTests.require(WorkspaceDisk.storedWorktreesDirectory(in: defaults).path == home.appendingPathComponent(".agentui").path,
                              "Worktrees go to the hidden ~/.agentui folder by default")
        defaults.set("", forKey: WorkspaceDisk.worktreesDirectoryKey)
        try CoreTests.require(WorkspaceDisk.storedWorktreesDirectory(in: defaults) == WorkspaceDisk.defaultWorktreesDirectory,
                              "An empty folder falls back to the default")
        defaults.set("~/Worktrees/", forKey: WorkspaceDisk.worktreesDirectoryKey)
        try CoreTests.require(WorkspaceDisk.storedWorktreesDirectory(in: defaults).path == home.appendingPathComponent("Worktrees").path,
                              "A stored folder expands the tilde")
        defaults.set(["~/agentui", "", "relative", "/tmp/worktrees"], forKey: WorkspaceDisk.scannedWorktreesDirectoriesKey)
        try CoreTests.require(WorkspaceDisk.storedScannedWorktreesDirectories(in: defaults).map(\.path) == [home.appendingPathComponent("agentui").path, "/tmp/worktrees"],
                              "Scanned folders keep only absolute paths")
        let legacySuite = "AgentUI.SettingsTests.Legacy.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        let legacy = FileManager.default.temporaryDirectory.appendingPathComponent("agentui-legacy-\(UUID().uuidString)")
        WorkspaceDisk.scanLegacyWorktreesDirectory(in: legacyDefaults, legacy: legacy)
        try CoreTests.require(WorkspaceDisk.storedScannedWorktreesDirectories(in: legacyDefaults).isEmpty, "A missing legacy folder is not scanned")
        legacyDefaults.removeObject(forKey: WorkspaceDisk.legacyWorktreesDirectoryCheckedKey)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: legacy) }
        WorkspaceDisk.scanLegacyWorktreesDirectory(in: legacyDefaults, legacy: legacy)
        try CoreTests.require(WorkspaceDisk.storedScannedWorktreesDirectories(in: legacyDefaults).map(\.path) == [legacy.standardizedFileURL.path],
                              "Worktrees left in the former ~/agentui folder keep being found")
        legacyDefaults.removeObject(forKey: WorkspaceDisk.scannedWorktreesDirectoriesKey)
        WorkspaceDisk.scanLegacyWorktreesDirectory(in: legacyDefaults, legacy: legacy)
        try CoreTests.require(WorkspaceDisk.storedScannedWorktreesDirectories(in: legacyDefaults).isEmpty, "A removed legacy folder doesn’t come back")
        print("PASS worktree folder settings")

        var appearance = TerminalAppearance()
        try CoreTests.require(appearance.palette == nil && !appearance.isEditable, "The system theme follows macOS and is not editable")
        appearance.setColor(TerminalColor(hex: 0xFF0000), at: \.background)
        try CoreTests.require(appearance.theme == .system, "Editing the system theme is ignored")
        appearance.select(.dracula)
        appearance.setColor(TerminalColor(hex: 0x123456), at: \.ansi[1])
        try CoreTests.require(appearance.theme == .custom, "Editing a preset switches to the custom theme")
        try CoreTests.require(appearance.palette?.ansi[1] == TerminalColor(hex: 0x123456), "The edited color is kept")
        try CoreTests.require(appearance.palette?.background == TerminalPalette.dracula.background, "Other colors come from the edited preset")
        try CoreTests.require(TerminalTheme.allCases.compactMap(\.palette).allSatisfy { $0.ansi.count == 16 }, "Every preset defines 16 ANSI colors")
        let decodedAppearance = try JSONDecoder().decode(TerminalAppearance.self, from: JSONEncoder().encode(appearance))
        try CoreTests.require(decodedAppearance == appearance, "Terminal appearance round-trips")
        print("PASS terminal appearance settings")

        var confirmations = RemovalConfirmations()
        let id = UUID(), worktree = Removal.worktree(projectID: id, worktreeID: id, name: "feature")
        try CoreTests.require(confirmations.requires(.project(id)) && confirmations.requires(.terminal(id)), "Removals are confirmed by default")
        confirmations.skip(.terminal(id))
        try CoreTests.require(!confirmations.requires(.terminal(id)) && confirmations.requires(.project(id)), "Skipping is per removal kind")
        confirmations.skip(worktree)
        try CoreTests.require(confirmations.requires(worktree), "Worktree deletion always asks for confirmation")
        let decodedConfirmations = try JSONDecoder().decode(RemovalConfirmations.self, from: JSONEncoder().encode(confirmations))
        try CoreTests.require(decodedConfirmations == confirmations, "Removal confirmations round-trip")
        print("PASS removal confirmations")

        try runAgentSkill()
    }

    private static func runAgentSkill() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agentui-skill-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let skill = { (version: Int) in "---\nname: agentui\nmetadata:\n  version: \"\(version)\"\n---\nv\(version)\n" }
        let read = { (directory: URL) in try? String(contentsOf: directory.appending(path: "SKILL.md"), encoding: .utf8) }
        let repository = try String(contentsOf: URL(fileURLWithPath: "skills/agentui/SKILL.md"), encoding: .utf8)
        try CoreTests.require(AgentSkillInstaller.version(of: repository) > 0, "The repository skill declares a readable version")
        try CoreTests.require(AgentSkillInstaller.version(of: "---\r\nmetadata:\r\n  version: 4 # bump\r\n---\r\n") == 4, "Versions tolerate CRLF and comments")
        try CoreTests.require(AgentSkillInstaller.version(of: "no frontmatter") == 0, "A file without frontmatter has no version")

        let installer = AgentSkillInstaller(content: skill(2), home: home)
        try CoreTests.require(installer.status == .notInstalled, "The skill starts uninstalled")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Installing writes the skill")
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: installer.claudeDirectory.path)
        try CoreTests.require(link == installer.sharedDirectory.path, "Claude skills link to the shared copy")

        try installer.uninstall()
        try AgentSkillInstaller(content: skill(1), home: home).install()
        try CoreTests.require(installer.status == .outdated, "An older installed version is outdated")
        try installer.install()
        try CoreTests.require(installer.status == .installed && read(installer.claudeDirectory) == skill(2), "Updating replaces an older version")

        try AgentSkillInstaller(content: skill(3), home: home).install()
        try CoreTests.require(installer.status == .installed, "A newer version installed elsewhere is up to date")
        try installer.install()
        try CoreTests.require(read(installer.sharedDirectory) == skill(3), "Installing never downgrades the shared copy")

        try installer.uninstall()
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try Data(skill(3).utf8).write(to: installer.claudeDirectory.appending(path: "SKILL.md"))
        try CoreTests.require(installer.status == .incomplete, "A single current copy is incomplete, not outdated")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Repairing completes the installation")
        try CoreTests.require(read(installer.claudeDirectory) == skill(3) && read(installer.sharedDirectory) == skill(3), "Repairing keeps the newer Claude copy")

        try installer.uninstall()
        try installer.install()
        try FileManager.default.removeItem(at: installer.claudeDirectory)
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try Data(skill(1).utf8).write(to: installer.claudeDirectory.appending(path: "SKILL.md"))
        try CoreTests.require(installer.status == .incomplete, "A stale Claude copy is incomplete")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Installing replaces a stale Claude copy")

        try installer.uninstall()
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try Data(skill(1).utf8).write(to: installer.claudeDirectory.appending(path: "SKILL.md"))
        try Data("notes".utf8).write(to: installer.claudeDirectory.appending(path: "notes.md"))
        try installer.install()
        try CoreTests.require(installer.status == .installed && FileManager.default.fileExists(atPath: installer.claudeDirectory.appending(path: "notes.md").path),
                              "Updating a real Claude folder keeps the user's other files")
        try installer.uninstall()
        try CoreTests.require(installer.status == .notInstalled && FileManager.default.fileExists(atPath: installer.claudeDirectory.appending(path: "notes.md").path),
                              "Uninstalling keeps the user's other files")
        try FileManager.default.removeItem(at: installer.claudeDirectory)
        try installer.install()

        let configuration = home.appending(path: "claude-config")
        let configured = AgentSkillInstaller(content: skill(2), home: home.appending(path: "configured"), claudeConfiguration: configuration)
        try CoreTests.require(configured.claudeDirectory.path == configuration.appending(path: "skills/agentui").path, "CLAUDE_CONFIG_DIR moves the Claude skills folder")

        let sharedHome = home.appending(path: "shared")
        try FileManager.default.createDirectory(at: sharedHome.appending(path: ".agents/skills"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedHome.appending(path: ".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: sharedHome.appending(path: ".claude/skills").path,
                                                   withDestinationPath: sharedHome.appending(path: ".agents/skills").path)
        let linkedHome = AgentSkillInstaller(content: installer.content, home: sharedHome)
        try linkedHome.install()
        try linkedHome.install()
        try CoreTests.require(linkedHome.status == .installed, "A Claude skills folder linked to the shared one keeps the skill")

        try installer.uninstall()
        try CoreTests.require(installer.status == .notInstalled, "Uninstalling removes both copies")
        try installer.uninstall()
        print("PASS agent skill installer")

        let bin = home.appending(path: "bin")
        let app = home.appending(path: "AgentUI.app/Contents/MacOS/AgentUI")
        let command = CommandLineInstaller(executable: app, directory: bin)
        try CoreTests.require(command.status == .notInstalled, "The command starts outside PATH")
        try command.install()
        try CoreTests.require(command.status == .installed, "Installing links the command")
        try CoreTests.require((try? FileManager.default.destinationOfSymbolicLink(atPath: command.link.path)) == app.path, "The command links to the app executable")
        let moved = CommandLineInstaller(executable: home.appending(path: "Moved/AgentUI.app/Contents/MacOS/AgentUI"), directory: bin)
        try CoreTests.require(moved.status == .outdated, "A link to another AgentUI copy is outdated")
        try moved.install()
        try CoreTests.require(moved.status == .installed && command.status == .outdated, "Updating relinks to the running copy")
        try moved.uninstall()
        try CoreTests.require(moved.status == .notInstalled, "Uninstalling removes the link")
        try Data("#!/bin/sh\n".utf8).write(to: command.link)
        try CoreTests.require(command.status == .conflict, "A foreign file is a conflict")
        do { try command.install(); throw WorkspaceError(message: "FAIL: foreign command replaced") }
        catch let error as WorkspaceError { try CoreTests.require(error.message.contains("doesn’t belong"), "A foreign command is never replaced") }
        try command.uninstall()
        try CoreTests.require(FileManager.default.fileExists(atPath: command.link.path), "Uninstalling never removes a foreign file")
        try FileManager.default.removeItem(at: command.link)
        try FileManager.default.createSymbolicLink(atPath: command.link.path, withDestinationPath: "/usr/bin/true")
        try CoreTests.require(command.status == .conflict, "A link to another program is a conflict")
        try FileManager.default.removeItem(at: command.link)
        let translocated = CommandLineInstaller(executable: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/1/d/AgentUI.app/Contents/MacOS/AgentUI"), directory: bin)
        do { try translocated.install(); throw WorkspaceError(message: "FAIL: translocated app linked") }
        catch let error as WorkspaceError { try CoreTests.require(error.message.contains("Applications"), "A translocated app is never linked") }
        try CoreTests.require(translocated.status == .notInstalled, "A refused installation leaves nothing behind")
        print("PASS agent command installer")
    }
}
