# Verification — 2026-10-28

Core tests passed: folder import filtering, persistence round-trip and corrupt-file preservation, CLI argument/context validation, real Git worktrees, duplicate-branch and option rejection.

Integration tests passed against a native Debug app with disposable state/repositories: real PTY and working directory, literal command arguments, child terminal creation from inside a parent terminal, worktree creation, duplicate-branch failures, concurrent refresh/create, virtual grouping, session selection, restart persistence, no automatic replay of agent commands, read-only corruption recovery protection.

Independent code review identified and verified fixes for refresh/create concurrency and read-only mutation gating.

Visual acceptance is unverified. Stage Manager exposed only a transformed thumbnail; screencapture of the original window failed and ScreenCaptureKit returned -3811. Offscreen cacheDisplay snapshots omitted native vibrancy and text colors, so these invalid captures were discarded. No visual defect or appearance pass is inferred from them. Validate normal-window appearance, keyboard traversal and VoiceOver on the Mac.

## Repository import and branch badges

Scoped code review findings addressed: selected container symlinks are resolved, inaccessible descendants are reported while accessible repositories are imported. Core tests cover root discovery, unborn/detached/worktree HEAD, relative gitfiles, aliases, permissions and legacy saved folders. Native app integration passed automatic parent-folder import, idempotent reimport, live branch switches, shell cd between repositories and leaving Git. The badges consume those observed per-terminal values; native visual inspection remains unverified under the capture limitations above.

## Terminal closing and native inspector

Source documentation updated for Command-W terminal closure, project sleep/wake presentation, and the native SwiftUI inspector (Files, Agents, Git, Checks). The inspected implementation includes lazy directory loading, read-only file/diff previews, terminals grouped by worktree, local Git status, and `gh` repository/PR/checks/Actions queries. PR checks and local-HEAD Actions are explicitly distinguished. Inspector reads use cancellable subprocesses with timeout/output limits; Git/Checks include local and remote refresh intervals and manual refresh.

Core tests passed for NUL status parsing, staged/unstaged diffs, individual untracked file previews, explorer symlink boundaries, bounded file previews, gh JSON schemas, no-PR/network failures, cancellation, timeout and live output limits. Native app integration passed keyboard Command-W and the Close menu, last-terminal dormancy, reopening, same-project selection, persisted dormant state, and window closure without a selected terminal. Live read-only gh queries against stablyai/orca confirmed PR/checks/Actions JSON fields. Debug and Release builds passed. Independent review confirmed fixes for untracked directory preview, cache recovery and subprocess output limits. The visual acceptance limitations above remain unchanged.

The user then requested the Add menu in the projects list toolbar: it now lives in the sidebar header above the filter, rather than the window toolbar.

## SwiftUI specialist review corrections and application icon

All eight review findings addressed: cancellable/deadlined Git commands with owned process groups and partial-worktree reconciliation; durable CLI acknowledgements and retryable persistence errors; coalesced, revision-ordered actor writes with quit flushing; independent observable workspace properties, extracted sidebar/row/footer views and cached filtering; literal Git diff pathspecs; independent structured local/remote inspector loops with stale-response checks; lazy change rows; UTF-8 scalar-safe preview truncation.

Core and store regression suites passed, including cancellation of a blocked post-checkout hook, preserved partial worktrees, output/time limits, UTF-8 boundaries, literal diff paths, old-write rejection, independent polling, observation isolation, coalesced flush, write failure/retry and sidebar filtering. Native app integration passed CLI write-failure responses/retry and partial-worktree recovery as well as PTYs, inherited agent context, worktree creation, import, restart and corrupt-state protection. The final integration run explicitly used AGENTUI_SKIP_WINDOW_TESTS=1: WindowServer refused the test window keyboard focus despite activation attempts, so shortcut/window checks were skipped rather than reported passing. Earlier full runs are recorded above. Visual acceptance remains unverified.

Debug and Release builds passed. The user's Desktop/AgentUI.icon package was copied byte-for-byte to AgentUI/AgentUI.icon, configured as ASSETCATALOG_COMPILER_APPICON_NAME in both configurations, and verified in compiled CFBundleIconName/CFBundleIconFile with the generated Release AgentUI.icns.
