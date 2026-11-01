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
        let installer = AgentSkillInstaller(content: skill(2), home: home)
        try CoreTests.require(installer.version == 2 && AgentSkillInstaller.version(of: "no frontmatter") == 0, "The skill version comes from its frontmatter")
        try CoreTests.require(installer.status == .notInstalled, "The skill starts uninstalled")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Installing writes the skill")
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: installer.claudeDirectory.path)
        try CoreTests.require(link == installer.sharedDirectory.path, "Claude skills link to the shared copy")

        try AgentSkillInstaller(content: skill(1), home: home).uninstall()
        try AgentSkillInstaller(content: skill(1), home: home).install()
        try CoreTests.require(installer.status == .outdated, "An older installed version is outdated")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Updating replaces an older version")

        let newer = AgentSkillInstaller(content: skill(3), home: home)
        try newer.install()
        try CoreTests.require(installer.status == .installed, "A newer version installed elsewhere is up to date")
        try installer.install()
        let kept = try String(contentsOf: installer.sharedDirectory.appending(path: "SKILL.md"), encoding: .utf8)
        try CoreTests.require(kept == skill(3), "Installing never downgrades a newer skill")

        try FileManager.default.removeItem(at: installer.claudeDirectory)
        try FileManager.default.createDirectory(at: installer.claudeDirectory, withIntermediateDirectories: true)
        try Data(skill(1).utf8).write(to: installer.claudeDirectory.appending(path: "SKILL.md"))
        try CoreTests.require(installer.status == .outdated, "A stale Claude copy is outdated")
        try installer.install()
        try CoreTests.require(installer.status == .installed, "Installing replaces a stale Claude copy")

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
    }
}
