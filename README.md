# AgentUI

[![CI](https://github.com/lebojo/AgentUI/actions/workflows/ci.yml/badge.svg)](https://github.com/lebojo/AgentUI/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)](https://www.apple.com/macos/)
[![Xcode](https://img.shields.io/badge/Xcode-27.1-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

A native macOS app to organize your projects, Git worktrees and coding agents (Claude, Codex…) in real terminals. A SwiftUI sidebar, a native inspector and an AppKit [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminal, with no WebView and no Electron. Inspired by the layout of [Orca](https://github.com/stablyai/orca).

## Features

- **Projects and virtual folders**: group repositories from anywhere on disk without ever moving files.
- **Folder import**: recursive Git repository discovery, idempotent reimport.
- **Git worktrees**: one branch per worktree, created in one click, each with its own terminals.
- **Real terminals**: native PTY, the user's shell, and a branch badge that follows the working directory.
- **Inspector**: files, agents, Git changes, diffs, pull request and GitHub Actions checks.
- **`agentui` CLI**: agents can create terminals and worktrees from inside their own terminal.
- **Agent usage**: remaining Claude and Codex plan limits, with reset countdowns, below the project list.
- **Persistence**: your organization is restored on relaunch.

## Requirements

- macOS 14 or later
- Xcode 27.1 (Swift 6.4)
- Optional: [`gh`](https://cli.github.com) installed and authenticated (`gh auth login`) for GitHub data in the inspector

## Download

Download `AgentUI.zip` from the [latest release](https://github.com/lebojo/AgentUI/releases/latest). The app is a universal build (Apple silicon and Intel), ad-hoc signed but not notarized, so on first launch:

1. Unzip the archive and move `AgentUI.app` to `/Applications`.
2. Open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**.

Or remove the quarantine attribute from Terminal: `xattr -dr com.apple.quarantine /Applications/AgentUI.app`.

## Installation

```sh
git clone git@github.com:lebojo/AgentUI.git
cd AgentUI
open AgentUI.xcodeproj
```

Select the **AgentUI / My Mac** scheme, then **Run** (⌘R).

Xcode resolves the Swift Package Manager dependencies on first launch:

| Dependency | Version |
| --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.20.0 (pinned) |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 |

Xcode may ask you to enable the `SwiftTermBuildInfoPlugin` plugin, which generates SwiftTerm's version information.

Command-line build:

```sh
xcodebuild -project AgentUI.xcodeproj -scheme AgentUI -configuration Debug \
  -derivedDataPath /tmp/agentui-build -skipPackagePluginValidation build CODE_SIGNING_ALLOWED=NO
```

## Usage

### Organization

- **+ in the project list header**: add projects, import a folder, create a virtual folder.
- **Add Project** also recognizes a folder containing several repositories and groups them automatically. **Import Folder** only looks for Git repositories and creates a virtual folder named after the chosen folder. Reimporting that folder keeps existing projects, their names and their terminals.
- Discovery walks subfolders, stops at each repository and skips hidden folders, macOS packages and common dependency directories (`node_modules`, `Pods`, `Carthage`, `DerivedData`, `venv`). Submodules inside a repository stay in that project. An inaccessible folder is reported without blocking the import of other repositories.
- **Right-click a project → Move To**, or drag and drop onto a virtual folder: group projects without moving files.
- **+ next to a project**: create a new Git branch from its HEAD in a separate worktree, then open a terminal in it. The repository must have at least one commit and the branch must not already exist. While creating, **Stop** interrupts Git and its hooks. Creation has a 90-second limit; a partial creation stays on disk and is reconciled in the list without opening a terminal. The message shows the branch and path to check before retrying.
- Terminals of the main folder appear directly under the project. Additional worktrees hold their own terminals. Existing worktrees are discovered when a project is added, then via **Refresh Worktrees**.
- A **green badge** shows the current branch next to each Git terminal and in its header. It follows branch and shell directory changes within about two seconds, without spawning periodic Git processes. Outside a repository it disappears; on a detached HEAD, a neutral badge shows the abbreviated commit.
- The context menu lets you rename and close a terminal, rename or remove a project, and dissolve a virtual folder.

### Agent usage

The bottom of the project list shows, for each signed-in agent, the 5-hour and weekly windows with a countdown to the next reset. The chevron collapses it to each agent's logo and session percentage (remembered across launches). Click it for a sheet with every window (including per-model weekly limits), extra usage credits and a Refresh button.

Usage comes from the agents' own sign-in, like Orca: Claude reads the `Claude Code-credentials` Keychain item (or `~/.claude/.credentials.json`) and queries `api.anthropic.com/api/oauth/usage`; Codex reads `~/.codex/auth.json` (or `$CODEX_HOME`) and queries `chatgpt.com/backend-api/wham/usage`. Tokens are only sent to their own provider and never stored or refreshed by AgentUI. Data refreshes every five minutes. In the sheet, **Sign In** next to a signed-out agent opens an AgentUI terminal running `claude` or `codex login` in the selected worktree (or the first project), then checks every five seconds for up to ten minutes until the usage appears. When no agent is signed in, the bar shows a single sign-in link; otherwise signed-out agents stay out of the bar. An expired session is reported until the agent runs again and renews it.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | Open a terminal in the selected worktree (same as **+ Terminal**) |
| ⌘W | Close the selected terminal and stop its process; with no terminal selected, close the window |

After ⌘W, the selection moves to another terminal in the same worktree, then in the same project if any remain. Closing a project's last terminal keeps the project and its worktrees: its name turns secondary with a moon icon, and clicking it reopens a terminal in its main worktree.

### Inspector

The right panel button in the toolbar shows or hides the SwiftUI inspector. Visibility and the last tab are remembered. Its context is the selected terminal's worktree, even if the shell later changes directory.

| Tab | Content |
| --- | --- |
| **Files** | Folders load on expansion, folders before files, `.git` and `.DS_Store` hidden. Symlinks and packages are not traversed. Read-only preview of UTF-8 text files, limited to 128 KiB. Open in the default app or in Finder. |
| **Agents** | Claude and Codex conversations recorded on disk for the worktree, most recent first. **Play** resumes one in a new terminal (`claude --resume` / `codex resume`). Claude sessions already running (from `claude agents --json`) are marked and cannot be opened twice. |
| **Git** | Branch, staged, unstaged and untracked changes; read-only diff or preview. Links to the GitHub repository and the branch's pull request. |
| **Checks** | Pull request checks and up to ten GitHub Actions runs for the local HEAD commit. A message flags PR checks that refer to a different commit. |

GitHub data goes through `gh`. The UI separately reports a missing CLI, access errors, no PR and no runs; local features remain usable without GitHub. The inspector is read-only: no commit, push, or PR creation or merge.

Git/Checks reread local state every five seconds while the tab is visible, independently of GitHub requests. Remote data is refreshed after sixty seconds, on branch or commit change, and via the Refresh button. Read commands are cancellable, non-interactive, with a twenty-second limit per command and output limits. A diff is limited to 512 KiB per staged/unstaged part; oversized output is reported.

### Agent commands

Every terminal gets the native `agentui` command in its PATH, along with `AGENTUI_PROJECT_ID` and `AGENTUI_WORKTREE_ID`. If a shell configuration replaces PATH entirely, use `"$AGENTUI_CLI"`.

```sh
agentui --help
agentui list

# New terminal in the same worktree, with a child agent
agentui terminal create --name "Review" -- claude "Review the changes"

# New worktree and child agent on a new branch
agentui worktree create --branch feature/tests --name "Tests" -- codex "Add the tests"

# Plain terminal, without starting an agent
agentui terminal create --name "Shell"

# Explicitly target another context (IDs returned by agentui list)
agentui terminal create --project UUID --worktree UUID --name "Review"
```

Commands return JSON with `ok`, `projectID`, `worktreeID`, `terminalID` and `path`. A failure returns a non-zero exit code. Programs after `--` receive their arguments verbatim, without shell interpolation. Creations requested by an agent do not change the terminal selected on screen.

The CLI waits for the save before reporting success. If the write fails after creation, it returns `ok: false` with the identifiers already created: retry the save in the app, without recreating the terminal. Claude, Codex and other tools must already be installed and authenticated on the Mac.

Communication uses a request mailbox private to the app instance, with no network port and no Node/Python dependency. The command runs the same native executable, in CLI mode.

## Data and lifetime

| Data | Location |
| --- | --- |
| Organization (projects, folders, terminals) | `~/Library/Application Support/AgentUI/workspace.json` |
| Worktrees created by the app | `~/Library/Application Support/AgentUI/Worktrees/` |

Saves are coalesced during interactions, then written off the UI thread. A banner reports unsaved changes and offers a retry. Quitting waits for the last write; a save failure cancels the quit to keep changes in memory. Removing a project from the UI deletes no files, branches or worktrees.

Sessions stay alive when switching terminals; their content stays in memory. Quitting the app stops the processes, after confirmation. On relaunch, names and the hierarchy come back; shells restart on selection, without automatically replaying previous agent commands.

The macOS sandbox is disabled so the real shell can reach developer tools and repositories, like a regular terminal. The UI grants no extra permissions to agents.

## Project structure

```
AgentUI/
├── AgentUI/
│   ├── MyApp.swift, ContentView.swift
│   ├── Models/       # Workspace, stores, bridge protocol, inspector models
│   ├── Services/     # Git, agentui CLI, bridge, command execution, persistence
│   ├── Views/        # Sidebar, terminal, inspector
│   └── AgentUI.icon  # Icon Composer icon
├── Tests/            # Unit tests (run.sh) and integration tests (integration.py)
└── AgentUI.xcodeproj
```

## Tests

```sh
# Unit tests (compiled with swiftc, no Xcode needed)
./Tests/run.sh

# Integration tests against a Debug app built in /tmp/agentui-build
python3 Tests/integration.py
```

Integration tests launch a Debug instance with temporary state and repositories, never the user's data. They check the real PTY, delegation from a terminal, paths, Git and persistence. Regression tests also cover write failures, save ordering, Observation isolation, stopping a stuck Git hook, partial worktree recovery and local reads during a slow GitHub request.

If the macOS session cannot focus the test window, `AGENTUI_SKIP_WINDOW_TESTS=1 python3 Tests/integration.py` runs the other scenarios and explicitly reports the skipped keyboard/window tests. Automated captures do not validate the native appearance under Stage Manager; visual inspection still has to be done in a normal window.

## Continuous integration

Every pull request and every push to `main` triggers the [CI](.github/workflows/ci.yml) workflow on a GitHub `xcode-27` runner: a Debug build of the app, then the unit tests. The `main` branch is protected: changes go through a pull request whose **Build** check must pass.

## Contributing

1. Create a branch from `main`.
2. Check the build and `./Tests/run.sh` locally.
3. Open a pull request; it can be merged once CI is green and conversations are resolved.

## Current limitations

No scrollback restoration, semantic agent state tracking, or worktree merging or deletion yet.

## License

AgentUI is dual-licensed:

- **Open source**: [GNU General Public License v3.0](LICENSE). You are free to use, modify and redistribute it, provided that any distributed derivative work is also released under the GPL-3.0 with its source code.
- **Commercial**: if you want to integrate AgentUI into a proprietary product or distribute it without the GPL obligations, a paid commercial license is available. Contact [contact@jordan-chap.com](mailto:contact@jordan-chap.com).

## Acknowledgements

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza for the terminal emulator
- [Orca](https://github.com/stablyai/orca) for the reference layout
