# AgentUI

[![CI](https://github.com/lebojo/AgentUI/actions/workflows/ci.yml/badge.svg)](https://github.com/lebojo/AgentUI/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)](https://www.apple.com/macos/)
[![Xcode](https://img.shields.io/badge/Xcode-27.1-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

A native macOS app to organize your projects, Git worktrees and coding agents (Claude, Codex, Copilot, OpenCode…) in real terminals. A SwiftUI sidebar, a native inspector and an AppKit [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminal, with no WebView and no Electron. Inspired by the layout of [Orca](https://github.com/stablyai/orca).

## Features

- **Projects and virtual folders**: group repositories from anywhere on disk without ever moving files.
- **Folder import**: recursive Git repository discovery, idempotent reimport.
- **Git worktrees**: one branch per worktree, created in one click, each with its own terminals.
- **Real terminals**: native PTY, the user's shell, and a branch badge that follows the working directory.
- **Split terminals**: split the current terminal to the right or below, as many times as needed.
- **Worktree groups**: gather a project's worktrees under a named group in the sidebar.
- **Inspector**: files, agents, Git changes, diffs, pull/merge request and GitHub Actions or GitLab pipeline checks.
- **`agentui` CLI**: agents can create terminals and worktrees from inside their own terminal.
- **Agent usage**: remaining Claude and Codex plan limits, with reset countdowns, below the project list.
- **Persistence**: your organization is restored on relaunch.

## Requirements

- macOS 14 or later
- Xcode 27.1 (Swift 6.4)
- Optional: [`gh`](https://cli.github.com) installed and authenticated (`gh auth login`) for GitHub data in the inspector
- Optional: [`glab`](https://gitlab.com/gitlab-org/cli) installed and authenticated (`glab auth login`) for GitLab data in the inspector

## Download

Download `AgentUI.zip` from the [latest release](https://github.com/lebojo/AgentUI/releases/latest), unzip it and move `AgentUI.app` to `/Applications`. The app is a universal build (Apple silicon and Intel), signed with a Developer ID and notarized by Apple.

To build from source instead, see below.

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

### iPhone and iPad companion

Select an iPhone or iPad destination with the same **AgentUI** scheme to build the companion (iOS/iPadOS 17+).
On the Mac, enable **Settings → Accès local**. On the mobile device, open **Réglages**, tap **Scanner un QR code** and point the camera at the code shown on the Mac. You can also enter the Mac's local IP address and pairing code by hand. The mobile app saves every paired Mac: tap one in **Réglages** to switch to it, swipe to forget it. If a Mac has several local addresses, the app tries each one and remembers the address that works. Keep the Mac awake with AgentUI running. Both apps must be built from compatible sources.

The companion shares the Mac's projects and running sessions. **Settings → Affichage des sessions** chooses Chat or Terminal for every session on that device; the same preference is available on macOS under **Settings → Affichage**. Changing it preserves the process and mounts only the chosen renderer. The inspector button stays in the detail toolbar: SwiftUI presents a sheet on iPhone and a trailing inspector when the iPad has room. Files, conversations, Git diffs and checks use the shared inspector views.

The local transport uses TCP port **52741** with TLS 1.2 (`TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`). The pre-shared key is derived from the pairing code with PBKDF2-SHA256, and the ephemeral key exchange keeps recorded sessions private even if the code leaks later. Devices without the code cannot connect, and traffic is encrypted. Both devices keep the code in the Keychain. **Générer un nouveau code** on the Mac revokes every paired device. Sharing is off by default. Do not forward the port to the internet.

For Claude Code, Chat follows the native JSONL transcript of the exact process running in the terminal. User messages, Markdown replies and collapsible tool results are distinct; terminal menus, spinners and shell echoes are not assistant messages. Association uses Claude's live session registry and process ancestry rather than choosing the latest conversation in the worktree. This requires a Claude version publishing the `sessions/<pid>.json` registry (the installed CLI supports it). Chat reads a custom `CLAUDE_CONFIG_DIR` from the running Claude process. The conversation list and usage only honour it when AgentUI itself sees it (for example through `launchctl setenv`), because macOS does not expose a value exported only in a shell profile. Codex and Copilot follow their own session journals; ordinary shells and OpenCode retain the explicitly labelled terminal-output fallback. Authentication, approvals and interactive agent menus remain available in Terminal; this is not a full structured-agent RPC adapter.

Transcript reads are incremental and file-event driven, shared between local and remote Chat viewers and released when unused. The first read is bounded to 2 MiB; displayed history to 200 rows / 256 KiB. Multiline prompts use bracketed paste followed by a separate submit key. The mobile terminal fits the host grid to the screen width and supports pinch zoom; changing the viewport or keyboard never independently resizes the emulator.

The workspace and session use a persistent, bidirectional connection. Changes are coalesced at most ten times per second, unchanged workspaces aren't transmitted, Chat doesn't transfer raw terminal bytes, and Terminal doesn't transfer chat messages. The Mac interprets terminal output once: the companion receives changed screen rows and keyboard modes, with a complete checkpoint on reconnect. Scrollback checkpoints retain at most 200 lines / 16,384 cells; Chat history is capped at 256 KiB. Mobile layout never changes the Mac’s terminal grid. The terminal mirror carries styled text and input modes; inline terminal images and OSC hyperlink metadata are not transported. Backgrounding the mobile app cancels its connection and inspector queries; the Mac's processes continue running.

The navigation shell, inspector, diff views and Chat UI are shared. Platform adapters live under `AgentUI/Platforms`; SDK-specific source exclusions in the Xcode target keep AppKit and UIKit out of shared views.

To validate the local protocol against an isolated Debug Mac app (the fixture binds only to loopback):

```sh
bash Tests/run.sh
python3 Tests/remote-integration.py /path/to/AgentUI.app/Contents/MacOS/AgentUI
```

### Organization

- **+ in the project list header**: add projects, import a folder, create a virtual folder.
- **Add Project** also recognizes a folder containing several repositories and groups them automatically. **Import Folder** only looks for Git repositories and creates a virtual folder named after the chosen folder. Reimporting that folder keeps existing projects, their names and their terminals.
- Discovery walks subfolders, stops at each repository and skips hidden folders, macOS packages and common dependency directories (`node_modules`, `Pods`, `Carthage`, `DerivedData`, `venv`). Submodules inside a repository stay in that project. An inaccessible folder is reported without blocking the import of other repositories.
- **Right-click a project → Move To**, or drag and drop onto a virtual folder: group projects without moving files.
- **+ next to a project**: create a new Git branch from its HEAD in a separate worktree, then open a terminal in it. The repository must have at least one commit and the branch must not already exist. While creating, **Stop** interrupts Git and its hooks. Creation has a 90-second limit; a partial creation stays on disk and is reconciled in the list without opening a terminal. The message shows the branch and path to check before retrying.
- **Right-click a worktree → Group**, or drag it onto a group: gather worktrees of the same project under a named group. Right-click a project → **New Worktree Group…** creates an empty one. Renaming or dissolving a group never touches the worktrees, their folders or their branches.
- Terminals of the main folder appear directly under the project. Additional worktrees hold their own terminals. Existing worktrees are discovered when a project is added, then via **Refresh Worktrees**.
- Every worktree in the creation folder (`~/.agentui` by default) and in the **Other Worktree Folders** listed in Settings › General is shown: a worktree whose main repository is a project joins it automatically, the others appear under **Orphans**. Right-click an orphan to add its repository as a project, show it in Finder or move it to the Trash (after confirmation). Regular clones in these folders are ignored.
- A **green badge** shows the current branch next to each Git terminal and in its header. A branch change is picked up as soon as Git writes it (FSEvents on the repository metadata), and the shell directory is read every two seconds, without spawning any Git process. Outside a repository it disappears; on a detached HEAD, a neutral badge shows the abbreviated commit.
- Each terminal row shows two lines: the terminal name, then its current branch (or worktree). When an agent runs in it, the row shows the agent's logo and a status chip: yellow **Working**, green **Ready** or orange **Waiting input**; plain terminals show no chip. Claude's status comes from its session file (`~/.claude/sessions`); for Codex, Copilot and OpenCode, an approval prompt on screen means waiting for input, output in the last two seconds means working, otherwise ready. Statuses refresh every second.
- A terminal is named after the agent conversation running in it (Claude, Codex, Copilot or OpenCode, the same titles as the **Agents** tab), otherwise **Terminal**. AgentUI finds the agent among the terminal's processes and its session (`~/.claude/sessions`, the Codex rollout or Copilot session it has open), and falls back to the conversation of that agent updated in the same folder since it started. The name follows the conversation every five seconds and is kept after the agent exits.
- The context menu lets you rename and close a terminal, rename or remove a project, and dissolve a virtual folder. A renamed terminal keeps its name; **Use the conversation name** gives it back its automatic name.

### Agent usage

The bottom of the project list shows, for each signed-in agent, the 5-hour and weekly windows with a countdown to the next reset. The chevron collapses it to each agent's logo and session percentage (remembered across launches). Click it for a sheet with every window (including per-model weekly limits), extra usage credits and a Refresh button.

Usage comes from the agents' own sign-in, like Orca: Claude reads the `Claude Code-credentials` Keychain item (or `~/.claude/.credentials.json`) and queries `api.anthropic.com/api/oauth/usage`; Codex reads `~/.codex/auth.json` (or `$CODEX_HOME`) and queries `chatgpt.com/backend-api/wham/usage`. Tokens are only sent to their own provider and never stored or refreshed by AgentUI. Data refreshes every five minutes while the window is visible. In the sheet, **Sign In** next to a signed-out agent opens an AgentUI terminal running `claude` or `codex login` in the selected worktree (or the first project), then checks every five seconds for up to ten minutes until the usage appears. When no agent is signed in, the bar shows a single sign-in link; otherwise signed-out agents stay out of the bar. An expired session is reported until the agent runs again and renews it.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | Open a terminal in the selected worktree (same as **+ Terminal**) |
| ⌘D | Split the selected terminal to the right |
| ⇧⌘D | Split the selected terminal below |
| ⌘W | Close the selected terminal and stop its process; with no terminal selected, close the window |

Split panes are regular terminals of the same worktree: they also appear in the sidebar, and selecting any of them shows the whole split. Clicking a pane focuses it; its × button (or ⌘W) closes it, and the last remaining pane takes the whole space again. The layout is restored on relaunch.

After ⌘W, the selection moves to the neighbouring pane of a split, otherwise to another terminal in the same worktree, then in the same project if any remain. Closing a project's last terminal keeps the project and its worktrees: its name turns secondary with a moon icon, and clicking it reopens a terminal in its main worktree.

### Inspector

The right panel button in the toolbar shows or hides the SwiftUI inspector. Visibility and the last tab are remembered. Its context is the selected terminal's worktree, even if the shell later changes directory.

| Tab | Content |
| --- | --- |
| **Files** | Folders load on expansion, folders before files, `.git` and `.DS_Store` hidden. Symlinks and packages are not traversed. Read-only preview of UTF-8 text files, limited to 128 KiB. Open in the default app or in Finder. |
| **Agents** | Claude, Codex, Copilot and OpenCode conversations recorded on disk for the worktree, most recent first: `~/.claude/projects`, `~/.codex/sessions`, `~/.copilot/session-state` and the `session` table of `~/.local/share/opencode/opencode.db` (OpenCode subagent and archived sessions are left out). **Play** resumes one in a new terminal (`claude --resume` / `codex resume` / `copilot --resume` / `opencode --session`). Claude sessions already running (from `claude agents --json`) are marked and cannot be opened twice. |
| **Git** | Branch, staged, unstaged and untracked changes; read-only diff or preview. Links to the GitHub or GitLab repository and the branch's pull or merge request. |
| **Checks** | Pull request checks (or the jobs of the merge request's pipeline) and up to ten GitHub Actions runs or GitLab pipelines for the local HEAD commit. A message flags checks that refer to a different commit. |

GitHub data goes through `gh`, GitLab data through `glab api` (gitlab.com and self-hosted instances). The repository is treated as GitLab when the host of its `origin` remote (or its first remote) contains `gitlab`, and as GitHub otherwise. The UI separately reports a missing CLI, access errors, no PR/MR and no runs; local features remain usable without GitHub or GitLab. The inspector is read-only: no commit, push, or PR creation or merge.

Git/Checks reread local state when a file of the worktree or its Git metadata changes (FSEvents, coalesced over one second), independently of GitHub requests; nothing runs while the repository is idle. `git config` is only listed again when a configuration file, one of its include targets or HEAD changes. Remote data is refreshed every sixty seconds, on branch or commit change, and via the Refresh button (⌘R). The Agents tab follows the agents' session folders the same way. Every background refresh pauses while the window is hidden or fully covered. Read commands are cancellable, non-interactive, with a twenty-second limit per command and output limits. A diff is limited to 512 KiB per staged/unstaged part; oversized output is reported.

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

# Delete a worktree (IDs returned by agentui list); --force also erases uncommitted changes
agentui worktree delete --worktree UUID
```

Commands return JSON with `ok`, `projectID`, `worktreeID`, `terminalID` and `path`. A failure returns a non-zero exit code. Programs after `--` receive their arguments verbatim, without shell interpolation. Creations requested by an agent do not change the terminal selected on screen.

`worktree delete` closes the worktree's terminals and removes its folder, like **Delete Worktree…** in the sidebar; the branch and its commits stay in the repository. It always needs an explicit `--worktree`, refuses the project's main folder and the worktree of the calling terminal, and keeps a worktree with uncommitted changes or untracked files unless `--force` is given.

The CLI waits for the save before reporting success. If the write fails after creation, it returns `ok: false` with the identifiers already created: retry the save in the app, without recreating the terminal. Claude, Codex, Copilot, OpenCode and other tools must already be installed and authenticated on the Mac. Commands run through your interactive login shell, so a tool installed via npm, nvm, bun or any PATH set in `~/.zshrc` is found like in a regular terminal.

To use `agentui` from any terminal, click **Install** next to **Command in PATH** in **Settings → Agents**: it links `~/.local/bin/agentui` to the app, so add that folder to your PATH if needed. Outside AgentUI terminals, the CLI reaches the most recently launched AgentUI that is still running, registered in `~/Library/Application Support/AgentUI/Instances`, and the project and worktree come from the current directory when it belongs to a project open in AgentUI (otherwise pass `--project`).

To teach agents when and how to use these commands, install the `agentui` skill from **Settings → Agents → agentui command**. It is written to `~/.agents/skills/agentui` (read by Codex) and linked from `~/.claude/skills/agentui` (read by Claude Code, and by Copilot and OpenCode). Agents use it in AgentUI terminals (`AGENTUI_INSTANCE` set), and elsewhere only when you ask them to drive AgentUI.

The skill lives in [`skills/agentui`](skills/agentui/SKILL.md), so it can also be installed and updated without a new app release:

```sh
npx skills add LeBojo/AgentUI --skill agentui --global
npx skills update
```

The app bundles the same file and compares the `metadata.version` field: Settings offers an update only when the bundled version is newer, and never replaces a newer skill installed from GitHub.

Communication uses a request mailbox private to the app instance, with no network port and no Node/Python dependency. The command runs the same native executable, in CLI mode.

## Data and lifetime

| Data | Location |
| --- | --- |
| Organization (projects, folders, terminals) | `~/Library/Application Support/AgentUI/workspace.json` |
| Worktrees created by the app | `~/.agentui/<project>-<branch>/` (configurable in Settings › General) |

Saves are coalesced during interactions, then written off the UI thread. A banner reports unsaved changes and offers a retry. Quitting waits for the last write; a save failure cancels the quit to keep changes in memory. Removing a project from the UI deletes no files, branches or worktrees.

Sessions stay alive when switching terminals; their content stays in memory. Quitting the app stops the processes, after confirmation. On relaunch, names and the hierarchy come back; shells restart on selection, without automatically replaying previous agent commands.

The macOS sandbox is disabled so the real shell can reach developer tools and repositories, like a regular terminal. The UI grants no extra permissions to agents. Git commands started by the app, including those run by `gh`, ignore the repository's `core.fsmonitor` setting. The inspector's automatic reads (`git status`, `git diff`) also disable the filter drivers configured by the repository and skip submodule work trees, so displaying an untrusted repository does not run the programs it configures. Actions you start yourself, such as creating a worktree, behave like Git in a terminal: hooks and filters such as Git LFS still run.

## Project structure

```
AgentUI/
├── AgentUI/
│   ├── MyApp.swift
│   ├── Core/         # Remote channel, security, chat journals and terminal mirror
│   ├── Models/       # Workspace, stores, bridge protocol, inspector models
│   ├── Services/     # Git, agentui CLI, bridge, command execution, persistence
│   ├── Platforms/    # macOS and iOS adapters
│   ├── Views/        # One folder per screen (ContentView, WorkspaceSidebar, TerminalDetail, …), one view per file
│   │   └── Components/  # Views shared between screens
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

# Companion integration (isolated Mac host, real TCP + PTY)
python3 Tests/remote-integration.py /tmp/agentui-mobile-build/Build/Products/Debug/AgentUI.app/Contents/MacOS/AgentUI

# Terminal checkpoints + UIKit regression app in a disposable simulator.
# First build macOS and iOS Simulator Debug into these derived-data directories.
bash Tests/run-terminal-mirror.sh /tmp/agentui-mobile-build /tmp/agentui-ios-build
```

Integration tests launch a Debug instance with temporary state and repositories, never the user's data. Companion integration tests use a dynamically allocated loopback port and verify the fixture path before sending input, so an already-running Mac host is never used. With `Tests/remote-integration.py --hold` (app path before `--hold`), launch a disposable iPhone simulator with `SIMCTL_CHILD_AGENTUI_TEST_HOST_PORT` set to the printed port, and pass `-remoteHost 127.0.0.1 -remotePairingCode <printed code>` as launch arguments. `AGENTUI_SIM=<UDID> SERVE_SIM_ROOT=<serve-sim/dist> node Tests/mobile-navigation.cjs` checks project/worktree expansion, terminal navigation and back navigation through real UI taps. They check the real PTY, delegation from a terminal, paths, Git and persistence. Regression tests also cover write failures, save ordering, Observation isolation, stopping a stuck Git hook, partial worktree recovery and local reads during a slow GitHub request.

If the macOS session cannot focus the test window, `AGENTUI_SKIP_WINDOW_TESTS=1 python3 Tests/integration.py` runs the other scenarios and explicitly reports the skipped keyboard/window tests. Automated captures do not validate the native appearance under Stage Manager; visual inspection still has to be done in a normal window.

## Continuous integration

Every pull request and every push to `main` triggers the [CI](.github/workflows/ci.yml) workflow on a GitHub `xcode-27` runner: a Debug build of the app, then the unit tests. The `main` branch is protected: changes go through a pull request whose **Build** check must pass.

## Contributing

1. Create a branch from `main`.
2. Check the build and `./Tests/run.sh` locally.
3. Open a pull request; it can be merged once CI is green and conversations are resolved.

## Current limitations

No scrollback restoration after quitting the app, semantic agent state tracking, or worktree merging or deletion yet.

## License

AgentUI is dual-licensed:

- **Open source**: [GNU General Public License v3.0](LICENSE). You are free to use, modify and redistribute it, provided that any distributed derivative work is also released under the GPL-3.0 with its source code.
- **Commercial**: if you want to integrate AgentUI into a proprietary product or distribute it without the GPL obligations, a paid commercial license is available. Contact [contact@jordan-chap.com](mailto:contact@jordan-chap.com).

## Acknowledgements

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza for the terminal emulator
- [Orca](https://github.com/stablyai/orca) for the reference layout
