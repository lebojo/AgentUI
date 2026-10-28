# AgentUI

<!-- impeccable:product-schema 1 -->

## Platform
macOS, native desktop application.

## Stack
SwiftUI for the application and sidebar; AppKit is allowed for the embedded terminal.

## Product Purpose
A focused native alternative to Orca for organizing projects and agents. The workspace combines a left sidebar, an interactive terminal, and a native right inspector for the selected worktree.

## Capabilities and Constraints
- Virtual folders group projects that live in different filesystem locations.
- Importing a physical folder creates a UI group containing its child projects.
- Terminals can be added and named under projects and worktrees. Agents can create sibling terminals and Git worktrees using a local CLI; full orchestration is outside this iteration.
- The main view displays a real terminal. Command-W closes the selected terminal; with no selected terminal, it closes the window. A project with no remaining terminals stays in the sidebar asleep and can be reopened by clicking its name.
- The optional native inspector offers Files, Agents, Git and Checks. Files load directories on expansion and provide read-only text previews; Agents lists project terminals grouped by worktree.
- Git shows local changes and read-only diffs. GitHub repository, pull request, checks and Actions data use the installed, authenticated `gh` CLI. PR checks refer to the remote PR head; Actions are filtered to the current local HEAD commit.
- Git/Checks refresh local data every five seconds while visible, with remote refresh after sixty seconds or a branch/commit change. Manual refresh requests current data. Inspector subprocesses have time and output limits and support cancellation.
- Preserve organization across application launches; never move or delete project files when reorganizing the sidebar. Durable writes run off the UI actor, coalesce UI changes, and surface retryable failures. Agent commands acknowledge success only after persistence.
- Git worktree creation can be stopped, has a deadline and terminates its hook process group. Partial worktrees are preserved and reconciled without automatically launching a terminal.

## Brand Commitments
Orca is the user's interaction reference. Follow native macOS conventions and keep the interface focused.

## Open Decisions
Folder import discovers Git repository roots recursively, stopping at each repository and skipping hidden, package and dependency directories. Reimport is idempotent. Terminal branch badges follow the shell working directory and HEAD changes. Terminal sessions live for the application lifetime; shell processes do not survive quitting.

## Confirmed hierarchy
NavigationSplitView with virtual folders, projects, and open terminals; additional worktrees have their own nested terminals. A plus button on every project creates a worktree. The collapsible right inspector follows the selected terminal’s worktree; its Agents tab groups all terminals in that project by worktree.
