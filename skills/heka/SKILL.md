---
name: heka
description: Drive the Heka macOS app with the `heka` CLI. Use when the HEKA_INSTANCE environment variable is set (you are in a Heka terminal), or when the user asks to use Heka from another terminal. Use it to start another agent in parallel on its own branch (`heka worktree create`), to ask another agent for a review or a second opinion in the same worktree (`heka terminal create`), to run a long process such as a dev server or watcher in a visible terminal, to send a message or keys to another agent's terminal, read its reply or wait for it to finish (`heka terminal send`, `read`, `wait`), to close a terminal (`heka terminal close`), to add a project to the sidebar, to list projects, worktrees and terminals, or to delete a worktree once its branch is merged into the main branch, including your own worktree when the user asks you to merge your work and delete it. Prefer it over raw `git worktree add`, background jobs or a new shell when Heka is running.
metadata:
  version: "13"
---

# Heka CLI

Heka is a macOS app that organizes projects, Git worktrees and terminals in a sidebar. Every terminal it opens has the `heka` command in its PATH and these variables:

| Variable | Meaning |
| --- | --- |
| `HEKA_INSTANCE` | Set only inside a Heka terminal. |
| `HEKA_CLI` | Absolute path of `heka`, for shells that reset PATH. |
| `HEKA_PROJECT_ID`, `HEKA_WORKTREE_ID`, `HEKA_TERMINAL_ID` | The context of the current terminal. |

The floating terminal (⇧⌘T) belongs to no project and does not set the last three variables: as outside Heka, the project and worktree come from the current directory.

Check first: `test -n "$HEKA_INSTANCE" && heka list`.

Outside a Heka terminal, `heka` works only if the user installed it in their PATH (Settings → Agents) and Heka is running. The project and worktree then come from the current directory when it belongs to a project open in Heka; otherwise pass `--project UUID` from `heka list`. Do not use it outside Heka unless the user asked.

This skill may be newer or older than the installed app. `heka --help` is the reference for the installed version: read it when a command or option is refused.

## When to use it

- **Parallel work on another branch.** A self-contained task that should not touch the current working tree: `heka worktree create --branch <branch> -- <agent> "<prompt>"`.
- **Review or second opinion.** Another agent reads the current worktree: `heka terminal create --name Review -- <agent> "<prompt>"`.
- **Follow-up with a child.** Reply to a child that waits for input, ask it to fix its findings, or collect its result: `heka terminal send`, `wait` and `read` with the `terminalID` returned at creation.
- **Long-running process.** A dev server, test watcher or log tail that the user should see: `heka terminal create --name "Dev server" -- npm run dev`, instead of a background job in your own shell.
- **Cleanup.** Close the child terminals whose work is collected. Delete a worktree whose branch is merged into the main branch, after the user agrees, or your own worktree as your last action when the user asks you to merge and delete it.

## When not to use it

- The task is small enough to do yourself. Each child agent costs the user attention and usage.
- The user did not ask for parallel work and the task is not clearly separable. Propose it first.
- The child would only do a few seconds of work: doing it yourself is faster than sending, waiting and reading.

## Commands

```sh
heka list
heka project add /path/to/project
heka terminal create [--name NAME] [--project UUID] [--worktree UUID] [-- COMMAND ARGS…]
heka worktree create --branch BRANCH [--name NAME] [--project UUID] [-- COMMAND ARGS…]
heka worktree delete --worktree UUID [--delete-branch [--force-branch]] [--force]
heka terminal send --terminal UUID [--enter] (-- TEXT… | --stdin)
heka terminal send --terminal UUID --key KEY [--key KEY…]
heka terminal read --terminal UUID [--lines N | --reply | --messages N]
heka terminal wait --terminal UUID [--idle SECONDS | --exit] [--timeout SECONDS]
heka terminal close --terminal UUID [--force]
```

- Without `--project` or `--worktree`, commands target the current project and worktree. `--project` alone targets that project's main folder; `--worktree` alone finds its project.
- `heka list` prints the whole workspace as JSON: `projects[].id`, `projects[].path`, `projects[].worktrees[]` with `id`, `name` (the branch), `path`, `isPrimary` and `terminals[]`.
- Every other command prints `{"ok": true, "projectID": …, "worktreeID": …, "terminalID": …, "path": …}`. On failure: `{"ok": false, "message": …}` and a non-zero exit code. Read `message` and fix the call instead of retrying blindly.
- If a command times out after 120 seconds (`terminal wait`: its `--timeout` plus 30 seconds), the operation may still finish: run `heka list` before trying again.

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

## Talking to another terminal

Address a terminal with the `terminalID` returned by `terminal create` or `worktree create`, or found in `heka list`. These commands work on any terminal of the workspace, not only the ones you created. `send` and `wait` refuse your own terminal (`HEKA_TERMINAL_ID`); `read` and `close` accept it.

```sh
heka terminal send --terminal "$CHILD" --enter -- "Fix the findings of your review, then commit."
heka terminal wait --terminal "$CHILD" --idle 10 --timeout 110
heka terminal read --terminal "$CHILD" --reply
```

- `send` types the text into the terminal, as if on its keyboard. With `--enter`, it is submitted as one message, multi-line text included, like pressing Return in Claude, Codex, Copilot or OpenCode. Without `--enter`, the text is typed but not submitted. `--enter` alone presses Return, for example to accept a default choice. The text after `--` is joined with spaces and sent verbatim; for a long or multi-line message, pipe it with `--stdin` (`heka terminal send --terminal "$CHILD" --enter --stdin < prompt.md`). 64 KB at most.
- `--key` presses keys one after the other, in order: `enter`, `escape`, `tab`, `shift-tab`, `backspace`, `delete`, `space`, `up`, `down`, `left`, `right`, `home`, `end`, `page-up`, `page-down`, `ctrl-a` … `ctrl-z`. Use it to interrupt a child (`escape` for Claude, Codex and Copilot; `ctrl-c` for most other programs) or to move in a menu (`--key down --key enter`). It can't be combined with text: send the text in another command.
- `wait` returns once the terminal has printed nothing for `--idle` seconds (5 by default), counted from the call, or with `--exit` once its command has exited. An agent that works shows a spinner or a timer, so a quiet terminal usually means it finished or waits for an answer. It gives up after `--timeout` seconds (120 by default, 3600 at most) with `ok: false` and the current state. Keep `--timeout` below the time limit of your own shell tool, and call `wait` again if needed.
- `read --reply` returns in `output` the agent's answer to the last message it received, as plain text without the screen around it: menus, spinners and tool output are left out. It works for Claude, Codex and Copilot once the agent has recorded its conversation, and fails with a `message` otherwise. Prefer it to read a child's result.
- `read --messages N` returns the last N messages of the conversation (200 at most) in `messages`, each with `kind` (`input`, `assistant`, `tool` or `notice`), `text`, and for tools `title` and `toolState`.
- `read` alone returns the last `--lines` lines of the screen (50 by default, 10,000 at most) in `output`, wrapped lines joined. Use it for programs other than these agents, and to see what the child shows right now: a permission prompt or a menu appears on the screen, not in `--reply`.
- Each reply includes `running`, `exitCode` once the command has exited and, for a recognized agent, `agent` and `status` (`working`, `ready` or `waitingForInput`).
- Typical loop: `send --enter`, `wait --idle 10`, `read --reply`, decide; if `status` is `waitingForInput`, `read` the screen to see the prompt. Check `status` and the output before sending again: a message typed while the child is working is queued or mixed with its input, depending on the agent.
- Only send what the user asked for or what the task clearly calls for. Never approve a child's permission prompt, or answer for the user, unless they asked you to; report the prompt to them instead.
- To send the same message to several children, run `send` once per terminal.
- Sending to a terminal that has exited fails: create a new one, or resume the agent there.
- `close` stops the terminal's processes and removes it from the sidebar. Without `--force`, it refuses while the terminal's agent is `working`. Close the terminals you created once their work is collected; ask the user before closing one you didn't create, and before using `--force`. Closing your own terminal (`--terminal "$HEKA_TERMINAL_ID"`) replies first, then stops you: make it your last action.

## Limits

- `--reply` and `--messages` are not available for OpenCode or other programs: read the screen instead. For a large result, ask the child to commit it or write it to a file in its worktree.
- `heka` only works while Heka is running.

## Deleting a worktree

`heka worktree delete --worktree UUID` closes its terminals and deletes its folder. By default, the branch and its commits stay in the repository.

- Always ask the user before deleting, and say which worktree and branch.
- Without `--force`, a worktree with uncommitted changes or untracked files is kept and the command fails. Never add `--force` unless the user explicitly agrees to lose those changes.
- Add `--delete-branch` to delete the branch too, only when the user asked for it. The branch is deleted only if it is merged into the repository's main branch (`main`, `master` or a remote's `HEAD` branch, locally or on the remote once fetched). Otherwise, for example when the branch was only pushed or the repository has no main branch, nothing is removed: the command returns `ok: false` and a `message` explaining why. Report it to the user instead of retrying; with their agreement, run again without `--delete-branch` to delete only the worktree and keep the branch. With `--force-branch`, the branch is deleted even if it is not merged (`git branch -D`): its unmerged commits are lost, so never add it without the user's explicit agreement. `--force-branch` requires `--delete-branch`: on its own, the command fails before removing anything. `--force` only discards uncommitted changes in the worktree and never deletes an unmerged branch.
- The repository's main branch and a branch checked out in another worktree are never deleted, nor is a branch whose state can't be checked: the command fails before deleting anything.
- Once the worktree is deleted, the reply is `ok: true` with `removed: true`, plus `branch` and `branchDeleted` when a branch was asked for. `ok: false` always means nothing was removed. If the branch was kept anyway, for example because a commit landed on it after the merge check, `branchDeleted` is `false` and `message` says why: report it to the user, the worktree is already gone.
- The project's main folder cannot be deleted.

### Deleting your own worktree

When the user asks you to finish your work and delete your worktree ("merge into main and delete this worktree"), you can do it from the worktree itself: `heka worktree delete --worktree "$HEKA_WORKTREE_ID"`, with `--delete-branch` if the user asked for the branch to go too.

- To merge into the main branch first: it is checked out in the project's main folder, not in your worktree, so merge there with `git -C <main folder> merge <your branch>`, using the `path` of the worktree with `isPrimary: true` in `heka list`. Do not check out the main branch in your own worktree: Git refuses a branch checked out elsewhere. If the main folder has uncommitted changes or the merge conflicts, stop and ask the user.
- Everything is checked first, with the same rules as above. If the command refuses (`ok: false`), nothing is removed and you keep running: report the `message` to the user.
- Otherwise the reply is `ok: true` with `closesCaller: true`, then your terminal closes: you stop right away, without another turn, and the worktree is deleted. You can't report the final result.
- So make it your very last action: merge, push or whatever else the user asked, check that the worktree has no uncommitted changes, and tell the user what you did and that this terminal is about to close before running the command. Never add `--force` to get past uncommitted changes there unless the user explicitly agreed to lose them.
- The other terminals of the worktree close too. If the deletion still fails after the reply, Heka shows the error and reopens the worktree's terminals.
