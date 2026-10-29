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
    }
}
