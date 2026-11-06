# Agent instructions

## Releases

Never create a new version without asking the user first and getting an explicit yes. This covers:

- creating or pushing a Git tag (any tag push triggers `.github/workflows/release.yml`, which builds, signs, notarizes and publishes a GitHub release);
- creating, editing or deleting a GitHub release;
- changing `MARKETING_VERSION` or the version shown on the site.

Approval for one version does not carry over to the next one. When the user approves, the release is made with:

```sh
git tag -a <version> -m "Heka <version>"
git push origin <version>
```

## Agent skill

`skills/heka/SKILL.md` documents the `heka` CLI for agents and is bundled in the app. Update it with any change to the CLI (`Heka/Services/AgentCLI.swift`, `Heka/Services/AgentBridge.swift`), and increase `metadata.version` with every change to the file: the app relies on it to offer the new version in Settings (`npx skills update` detects changes on its own).

## TODO: remove the AgentUI migration after February 2027

The app was renamed from AgentUI to Heka in November 2026. The migration code only serves the developer's own Mac during the transition: from February 2027, remind the user and offer to delete it:

- `Heka/Services/AgentUIMigration.swift`, its call in `Heka/MyApp.swift`, its entry in the iOS `EXCLUDED_SOURCE_FILE_NAMES` of `Heka.xcodeproj/project.pbxproj` and in `Tests/run.sh`, and its strings in `Heka/Localizable.xcstrings` (“Quit AgentUI…”, “Quit Heka” (not “Quit Heka?”), “AgentUI is still open…”, “Heka takes over…”, “Some AgentUI data stayed behind”, “Heka already had its own copy…”);
- in `WorkspaceDisk`: `legacyApplicationDirectory`, `isLegacyWorktreesDirectory`, and the scan of the former worktree folders (`legacyWorktreesDirectories`, `legacyWorktreesDirectory(named:)`, `scanLegacyWorktreesDirectories` and `scanLegacyWorktreesDirectory`, with their call in `SettingsStore`). Folders found by the scan are already saved under Other Worktree Folders, so they stay listed;
- the matching tests in `Tests/SettingsTests.swift`: the former `~/agentui` folder scan and the “PASS AgentUI migration” block;
- the paragraph about AgentUI in the “Data and lifetime” section of `README.md`;
- then this section.

Also remind the user that they can delete by hand, once Heka holds everything: AgentUI.app, `~/Library/Application Support/AgentUI` (only instance registrations or items listed by the migration message are left there), the `ch.jordanchap.agentui` defaults (`defaults delete ch.jordanchap.agentui`), the `ch.jordanchap.agentui.pairing` keychain item, and the `~/agentui` and `~/.agentui` folders once their worktrees are no longer needed.

## Lint

SwiftUI views must declare their members in this order, with one blank line between sections and `private` where shown:

```swift
@AppStorage private var ...

@Environment private var ...
@EnvironmentObject private var ...

@State private var ...

@StateObject private var ...

@FocusState private var ...

@Binding var ...

@ObservedObject var ...
@ObservedRealmObject var ...
@ObservedResults private var ...
@Bindable var ...

let ...
private var ... {
}

var body: some View {}

private func ...
```

Check with `swift Scripts/lint-views.swift` and fix with `swift Scripts/lint-views.swift --fix`. Reordering stored properties changes the memberwise initializer, so update the call sites afterwards.
