---
name: agentui
description: Drive the AgentUI macOS app from inside one of its terminals with the `agentui` CLI. Use only when the AGENTUI_INSTANCE environment variable is set. Use it to start another agent in parallel on its own branch (`agentui worktree create`), to ask another agent for a review or a second opinion in the same worktree (`agentui terminal create`), to run a long process such as a dev server or watcher in a visible terminal, to add a project to the sidebar, to list projects, worktrees and terminals, or to delete a worktree once its branch is merged. Prefer it over raw `git worktree add`, background jobs or a new shell when AgentUI is running.
metadata:
  version: "1"
---

# AgentUI CLI

AgentUI is a macOS app that organizes projects, Git worktrees and terminals in a sidebar. Every terminal it opens has the `agentui` command in its PATH and these variables:

| Variable | Meaning |
| --- | --- |
| `AGENTUI_INSTANCE` | Set only inside an AgentUI terminal. If it is missing, this skill does not apply. |
| `AGENTUI_CLI` | Absolute path of `agentui`, for shells that reset PATH. |
| `AGENTUI_PROJECT_ID`, `AGENTUI_WORKTREE_ID`, `AGENTUI_TERMINAL_ID` | The context of the current terminal. |

Check first: `test -n "$AGENTUI_INSTANCE" && agentui list`.

This skill may be newer or older than the installed app. `agentui --help` is the reference for the installed version: read it when a command or option is refused.

## When to use it

- **Parallel work on another branch.** A self-contained task that should not touch the current working tree: `agentui worktree create --branch <branch> -- <agent> "<prompt>"`.
- **Review or second opinion.** Another agent reads the current worktree: `agentui terminal create --name Review -- <agent> "<prompt>"`.
- **Long-running process.** A dev server, test watcher or log tail that the user should see: `agentui terminal create --name "Dev server" -- npm run dev`, instead of a background job in your own shell.
- **Cleanup.** Delete a worktree whose branch is merged, after the user agrees.

## When not to use it

- The task is small enough to do yourself. Each child agent costs the user attention and usage.
- The user did not ask for parallel work and the task is not clearly separable. Propose it first.
- You would need the child's output to continue: see the limits below.

## Commands

```sh
agentui list
agentui project add /path/to/project
agentui terminal create [--name NAME] [--project UUID] [--worktree UUID] [-- COMMAND ARGS…]
agentui worktree create --branch BRANCH [--name NAME] [--project UUID] [-- COMMAND ARGS…]
agentui worktree delete --worktree UUID [--force]
```

- Without `--project` or `--worktree`, commands target the current project and worktree. `--project` alone targets that project's main folder.
- `agentui list` prints the whole workspace as JSON: `projects[].id`, `projects[].path`, `projects[].worktrees[]` with `id`, `name` (the branch), `path`, `isPrimary` and `terminals[]`.
- Every other command prints `{"ok": true, "projectID": …, "worktreeID": …, "terminalID": …, "path": …}`. On failure: `{"ok": false, "message": …}` and a non-zero exit code. Read `message` and fix the call instead of retrying blindly.
- If the command times out after 120 seconds, the operation may still finish: run `agentui list` before trying again.

## Starting a child agent

- Everything after `--` is passed verbatim, without shell interpretation: no `&&`, pipes, globs or `$VAR`. For shell syntax, use `-- sh -c '…'`.
- The terminal runs that command and nothing else. It ends when the command exits.
- Use the agent the user works with (`claude`, `codex`, `copilot`, `opencode`). Ask if unsure. Do not add permission-bypass flags unless the user asked for them.
- The child does not see your conversation. Write a prompt that stands alone: goal, relevant files, constraints, how to verify, and what to leave behind when done (commits on its branch, a summary file).
- Give terminals a short `--name`, and tell the user what you created: new terminals open in the background, without taking the focus.

## Worktrees

- `worktree create` opens an existing branch as it is. Otherwise it creates the branch from the HEAD of the project's main folder, not from the current worktree. The child does not get your uncommitted changes: commit them first, or push the branch and pass its name.
- A branch already checked out elsewhere is refused.
- Worktrees share the repository, so you can follow the child's work with `git log <branch>` or `git -C <path> status` and `git -C <path> diff`, using the `path` returned at creation.

## Limits

- You cannot read a child terminal's output, send it input or wait for it to finish. Coordinate through Git (commits on the child's branch) or files in its worktree, or let the user follow it on screen.
- `agentui` only works while the AgentUI instance that opened your terminal is running.

## Deleting a worktree

`agentui worktree delete --worktree UUID` closes its terminals and deletes its folder. The branch and its commits stay in the repository.

- Always ask the user before deleting, and say which worktree and branch.
- Without `--force`, a worktree with uncommitted changes or untracked files is kept and the command fails. Never add `--force` unless the user explicitly agrees to lose those changes.
- The project's main folder and the worktree of the calling terminal cannot be deleted. Run the command from another worktree.
