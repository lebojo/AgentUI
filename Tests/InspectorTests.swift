import Foundation

enum InspectorTests {
    static func run(root: URL, repository: URL, unborn: URL) async throws {
        let require = CoreTests.require
        let status = GitStatus.parse(Data(["# branch.oid 1234", "# branch.head main",
                                           porcelainEntry("2", "R.", 9, "renamed file"), "original\nfile", porcelainEntry("1", ".M", 8, "café.swift"), "? untracked",
                                           porcelainEntry("2", "CM", 9, " spaced  name"), "copied from", porcelainEntry("u", "UU", 10, "conflict"),
                                           porcelainEntry("1", "A.", 8, "\u{301}accent"), "! ignored", ""].joined(separator: "\0").utf8))
        try require(status.headSHA == "1234" && status.changes.map(\.path) == ["renamed file", "café.swift", "untracked", " spaced  name", "conflict", "\u{301}accent"]
                    && status.changes[0].originalPath == "original\nfile" && status.changes[0].status == "R" && status.changes[1].status == "M"
                    && status.changes[2].isUntracked && status.changes[3].originalPath == "copied from" && status.changes[3].status == "CM"
                    && status.changes[4].isConflicted && status.changes[5].isStaged && !status.changes[5].isUnstaged,
                    "Porcelain v2 parsing preserves renames, copies, conflicts, spaces, Unicode and newlines")
        let cut = GitStatus.parse(Data(["# branch.oid 1234", porcelainEntry("1", ".M", 8, "kept"), porcelainEntry("2", "R.", 9, "renamed"), "origi"]
            .joined(separator: "\0").utf8), isTruncated: true)
        try require(cut.isTruncated && cut.headSHA == "1234" && cut.changes.map(\.path) == ["kept"],
                    "A truncated status keeps its complete records and drops the cut one")
        let omission = { (truncated: Bool, bulk: Bool) in
            String(localized: WorkingTreeOmission(count: 3, isTruncated: truncated).message(includingBulkActions: bulk))
        }
        try require(omission(true, false) == "At least 3 more changes aren’t listed."
                    && omission(false, true) == "3 more changes aren’t listed. Stage All and Unstage All also apply to them."
                    && omission(true, true).hasPrefix("At least 3") && omission(false, false) == "3 more changes aren’t listed.",
                    "The working tree notice counts the hidden changes and mentions the bulk actions only when they exist")
        try require(StagedChangesSection(listsChanges: true, hasStagedChanges: true) == .listed
                        && StagedChangesSection(listsChanges: false, hasStagedChanges: true) == .unlisted
                        && StagedChangesSection(listsChanges: false, hasStagedChanges: false) == .hidden,
                    "Staged changes beyond the listed ones keep their section and Unstage All")
        let file = repository.appendingPathComponent("tracked file.txt")
        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "--", "tracked file.txt"], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=Heka Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "Tracked fixture"], at: repository.path)
        try "staged\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "--", "tracked file.txt"], at: repository.path)
        try "unstaged\n".write(to: file, atomically: true, encoding: .utf8)
        let newDirectory = repository.appendingPathComponent("new folder")
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        try "new text".write(to: newDirectory.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let local = try await InspectorService.localGit(at: repository.path)
        guard let untracked = local.changes.first(where: { $0.path == "new folder/new.txt" }) else { fatalError("New directory should expose individual files") }
        let untrackedPreview = try await InspectorService.diff(untracked, at: repository.path)
        let untrackedLines = untrackedPreview.sections.first?.lines.filter { $0.kind == .addition } ?? []
        try require(untrackedPreview.sections.map(\.kind) == [.untracked] && untrackedLines.map(\.text) == ["new text"]
                    && untrackedLines.last?.missingFinalNewline == true && untrackedPreview.sections[0].patch.contains("+++ b/new folder/new.txt"),
                    "Preview new files inside untracked directories as a new-file patch")
        guard let change = local.changes.first(where: { $0.path == "tracked file.txt" }) else { fatalError("Missing tracked change") }
        try require(change.status == "MM" && local.branch?.name == "main" && local.headSHA?.count == 40, "Real Git snapshot includes staged and unstaged state")
        let diff = try await InspectorService.diff(change, at: repository.path)
        try require(diff.sections.map(\.kind) == [.staged, .unstaged] && diff.sections[0].patch.contains("+staged") && diff.sections[1].patch.contains("+unstaged") && diff.onlySection == nil
                    && diff.sections[0].lines.contains(GitDiffLine(id: 2, kind: .addition, text: "staged", oldNumber: nil, newNumber: 1)),
                    "Preview both index and worktree diffs")
        let headOnly = try await InspectorService.localGit(at: repository.path, changesIn: [])
        let single = try await InspectorService.localGit(at: repository.path, changesIn: ["tracked file.txt"])
        try require(headOnly.changes.isEmpty && headOnly.headSHA == local.headSHA && single.changes.map(\.path) == ["tracked file.txt"]
                        && GitStatus.arguments(limitedTo: nil).contains("--branch") && !GitStatus.arguments(limitedTo: ["a"]).contains("--branch")
                        && GitStatus.arguments(limitedTo: ["a"]).suffix(2) == ["--", "a"],
                    "Remote checks skip git status and remote diffs only check the requested path, without counting ahead and behind")
        let empty = try await InspectorService.localGit(at: unborn.path)
        try require(empty.headSHA == nil && empty.tracking == nil && empty.branch?.name == "develop" && empty.changes.allSatisfy(\.isUntracked),
                    "Inspector supports unborn HEAD")
        print("PASS inspector status and real staged/unstaged diffs")

        let shell = URL(fileURLWithPath: "/bin/sh")
        let noisy = "yes hook output | head -c 200000 >&2; sleep 0.3"
        let kept = try await CommandRunner.run(shell, ["-c", noisy + "; echo done"], at: root.path, timeout: 10, limit: 1024, readOnly: false, overflow: .discard)
        try require(String(decoding: kept, as: UTF8.self) == "done\n", "Write commands keep running when a hook prints a lot")
        do {
            _ = try await CommandRunner.run(shell, ["-c", noisy + "; echo hook failed >&2; exit 1"], at: root.path, timeout: 10, limit: 1024,
                                            readOnly: false, overflow: .discard)
            throw WorkspaceError(message: "FAIL: failing hook accepted")
        } catch let error as ReadCommandError {
            try require(error.message.hasSuffix("hook failed"), "Discarded output still reports the latest diagnostic")
        }
        for pause in ["sleep 0.3; ", ""] {
            do {
                _ = try await CommandRunner.run(shell, ["-c", "yes hook output | head -c 200000 >&2; echo hook failed >&2; \(pause)exit 1"], at: root.path,
                                                timeout: 10, limit: 1024, readOnly: false, overflow: .discard)
                throw WorkspaceError(message: "FAIL: failing hook accepted")
            } catch let error as ReadCommandError {
                try require(error.message.contains("hook output\n") && error.message.hasSuffix("hook outhook failed"),
                            "A hook's final error survives, after the end of its output, the output discarded before it exits")
            }
        }
        for (script, expected) in [("echo nothing to commit; exit 1", "nothing to commit"),
                                   ("yes progress | head -c 180000; echo nothing added to commit; sleep 0.2; exit 1", "progress\nnothing added to commit"),
                                   ("exit 3", "The command failed (exit code 3)."),
                                   ("kill -9 $$", "The command was interrupted by signal 9 (\(String(cString: strsignal(9)))).")] {
            do {
                _ = try await CommandRunner.run(shell, ["-c", script], at: root.path, timeout: 10, limit: 0, readOnly: false, overflow: .discard)
                throw WorkspaceError(message: "FAIL: failing write accepted")
            } catch let error as ReadCommandError {
                try require(error.message.hasSuffix(expected), "A failing write reports its output when it has no error output, or its exit code: \(error.message)")
            }
        }
        let stubborn = Task {
            try await CommandRunner.run(shell, ["-c", "trap '' TERM; sleep 30"], at: root.path, timeout: 60, limit: 0, readOnly: false)
        }
        let quitLock = root.appendingPathComponent("quit.lock")
        let cleaning = Task {
            try await CommandRunner.run(shell, ["-c", "touch quit.lock; trap 'rm -f quit.lock; exit 143' TERM; while true; do sleep 0.05; done"],
                                        at: root.path, timeout: 60, limit: 0, readOnly: false)
        }
        try await Task.sleep(for: .milliseconds(300))
        let lockedBeforeQuit = FileManager.default.fileExists(atPath: quitLock.path)
        let killedAt = ContinuousClock.now
        CommandRunner.terminateAll()
        let quitDuration = killedAt.duration(to: .now)
        let lockedAfterQuit = FileManager.default.fileExists(atPath: quitLock.path)
        let stubbornResult = await stubborn.result
        let cleaningResult = await cleaning.result
        try require(lockedBeforeQuit && !lockedAfterQuit && (try? cleaningResult.get()) == nil,
                    "Quitting asks running commands to stop first, so a Git write can remove its lock")
        try require((try? stubbornResult.get()) == nil && quitDuration >= .milliseconds(400) && killedAt.duration(to: .now) < .seconds(1),
                    "Quitting kills the commands that ignore SIGTERM after a short wait")
        let obedient = Task {
            try await CommandRunner.run(shell, ["-c", "trap 'exit 143' TERM; while true; do sleep 0.05; done"], at: root.path, timeout: 60, limit: 0, readOnly: false)
        }
        try await Task.sleep(for: .milliseconds(300))
        let obedientQuitAt = ContinuousClock.now
        CommandRunner.terminateAll()
        try require(obedientQuitAt.duration(to: .now) < .milliseconds(400), "Quitting waits only until the stopped commands exit")
        _ = await obedient.result
        try require(CommandRunner.ExitStatus(waitStatus: 256) == .exited(1) && CommandRunner.ExitStatus(waitStatus: 0) == .exited(0)
                        && CommandRunner.ExitStatus(waitStatus: 15) == .signalled(15)
                        && CommandRunner.ExitStatus(waitStatus: 256).exitCode == 1 && CommandRunner.ExitStatus(waitStatus: 15).exitCode == nil,
                    "A wait status reads as an exit code or a signal")
        do {
            _ = try await CommandRunner.run(shell, ["-c", noisy], at: root.path, timeout: 10, limit: 1024, readOnly: true)
            throw WorkspaceError(message: "FAIL: oversized read accepted")
        } catch is ReadCommandError {}
        let endless = try await CommandRunner.run(shell, ["-c", "yes status line; exit 1"], at: root.path, timeout: 10, limit: 1024, readOnly: true, overflow: .truncate)
        try require(endless.count == 1024 && String(decoding: endless, as: UTF8.self).hasPrefix("status line\n"),
                    "A truncated read stops the command and keeps the beginning of its output")
        let endlessOutput = try await CommandRunner.output(shell, ["-c", "yes status line; exit 1"], at: root.path, timeout: 10, limit: 1024, readOnly: true,
                                                           overflow: .truncate)
        let exact = try await CommandRunner.output(shell, ["-c", "printf 1234"], at: root.path, timeout: 10, limit: 4, readOnly: true, overflow: .truncate)
        let over = try await CommandRunner.output(shell, ["-c", "printf 12345"], at: root.path, timeout: 10, limit: 4, readOnly: true, overflow: .truncate)
        try require(endlessOutput.isTruncated && !exact.isTruncated && exact.data == Data("1234".utf8)
                        && over.isTruncated && over.data == Data("1234".utf8),
                    "Output that exactly fills the limit is complete, output beyond it is reported as truncated")
        print("PASS write commands discard oversized output instead of stopping")

        try await branchComparison(root: root)
        try changeTree()
        try await workingTreeActions(root: root)
        try await publishing(root: root)
        try await porcelainStatus(root: root)
        try await gitRootCache(root: root)

        let patch = "diff --git a/f b/f\nindex 1..2 100644\n--- a/f\n+++ b/f\n@@ -3,4 +3,4 @@ func\n keep\n--- old\n-gone\n++++ new\n+\tadded\n same\n\\ No newline at end of file\n"
        let lines = GitDiffLine.parse(patch)
        try require(lines.map(\.kind) == [.hunk, .context, .deletion, .deletion, .addition, .addition, .context], "Parse hunks without mistaking content for headers")
        try require(lines[2].text == "-- old" && lines[2].oldNumber == 4 && lines[4].text == "+++ new" && lines[5].text == "\tadded" && lines[6].missingFinalNewline
                    && lines[5].newNumber == 5 && lines[6].oldNumber == 6 && lines[6].newNumber == 6, "Track old and new line numbers")
        let rows = GitDiffRow.pair(lines).map(\.content)
        guard rows.count == 5, case .pair(let changedOld, let changedNew) = rows[2], case .pair(let goneOld, let goneNew) = rows[3] else {
            fatalError("Side-by-side rows keep banners and context aligned")
        }
        try require(changedOld?.text == "-- old" && changedNew?.text == "+++ new" && goneOld?.text == "gone" && goneNew?.text == "\tadded",
                    "Side-by-side rows pair deletions with additions")
        let lonely = GitDiffRow.pair(GitDiffLine.parse("@@ -1,2 +1 @@\n-a\n-b\n+c\n")).map(\.content)
        guard lonely.count == 3, case .pair(let extra, nil) = lonely[2] else { fatalError("Unmatched deletions keep an empty right side") }
        try require(extra?.text == "b", "Unmatched deletions keep an empty right side")
        let noNewline = GitDiffLine.parse("@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n")
        let noNewlineRows = GitDiffRow.pair(noNewline).map(\.content)
        guard noNewlineRows.count == 2, case .pair(let before, let after) = noNewlineRows[1] else { fatalError("Missing final newline keeps the change paired") }
        try require(before?.text == "old" && after?.text == "new" && before?.missingFinalNewline == true && after?.missingFinalNewline == true,
                    "Missing final newline keeps the change paired")

        let combined = GitDiffLine.parse("diff --cc f\nindex a,b..c\n--- a/f\n+++ b/f\n@@@ -1,3 -1,1 +1,3 @@@\n  keep\n- --- gone\n++added\n +theirs\n")
        try require(combined.map(\.kind) == [.hunk, .context, .deletion, .addition, .addition] && combined[2].text == "--- gone"
                    && combined[2].oldNumber == 2 && combined[3].oldNumber == nil && combined[3].newNumber == 2
                    && combined[4].oldNumber == 3 && combined[4].newNumber == 3, "Parse combined diffs of conflicted files")

        let mixed = GitDiffSection(kind: .unstaged, patch: "@@ -1 +1 @@\n-a\n+a\r\n").lines
        let crlf = GitDiffSection(kind: .unstaged, patch: "@@ -1 +1 @@\n-a\r\n+b\r\n").lines
        try require(mixed[1].endingSymbols == "" && mixed[2].endingSymbols == "␍" && crlf.allSatisfy { $0.endingSymbols.isEmpty },
                    "Reveal carriage returns only when line endings change")

        let truncated = GitDiffSection.untracked(path: "f", content: TextContent(text: "a\nb", isTruncated: true), isExecutable: true)
        try require(truncated.additions == 2 && !truncated.isComplete && truncated.lines.last?.kind == .meta
                    && truncated.patch.contains("new file mode 100755") && !truncated.patch.contains("No newline"),
                    "Truncated untracked previews never count the notice as content")
        let deep = GitDiff(path: "f", sections: [GitDiffSection(kind: .unstaged, patch: "@@ -123456 +123456 @@\n-a\n+b\n")])
        try require(deep.lineNumberDigits == 6 && deep.onlySection?.additions == 1, "Gutter fits the widest line number")
        print("PASS diff parsing and side-by-side pairing")

        let entries = try await InspectorService.children(at: repository)
        try require(!entries.contains(where: { $0.name == ".git" }), "Hide Git internals")
        let link = root.appendingPathComponent("inspector-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let rootEntries = try await InspectorService.children(at: root)
        try require(rootEntries.first(where: { $0.name == link.lastPathComponent })?.isDirectory == false, "Explorer does not recurse symlink loops")
        let binary = root.appendingPathComponent("binary")
        try Data([0, 1, 2]).write(to: binary)
        do { _ = try await InspectorService.textFile(binary); throw WorkspaceError(message: "FAIL: binary preview accepted") }
        catch is ReadCommandError {}
        let big = root.appendingPathComponent("big.txt")
        try Data(repeating: 65, count: 150_000).write(to: big)
        let preview = try await InspectorService.textFile(big)
        try require(preview.contains("128 KB") && preview.count < 132_000, "Bound large text previews")
        print("PASS lazy explorer boundaries and bounded text preview")

        let fake = root.appendingPathComponent("fake-gh")
        let script = #"""
        #!/usr/bin/python3
        import sys,json,pathlib
        args=sys.argv[1:]
        with open(pathlib.Path(__file__).with_suffix('.calls'),'a') as f: f.write(json.dumps(args)+'\n')
        if args[:2] == ['repo','view']:
            print(json.dumps({'nameWithOwner':'fixture/app','url':'https://github.com/fixture/app','description':'Fixture'}))
        elif args[:2] == ['pr','view']:
            if args[2] == 'none':
                print('no pull requests found for branch "none"',file=sys.stderr);sys.exit(1)
            if args[2] == 'offline':
                print('error connecting to api.github.com',file=sys.stderr);sys.exit(1)
            print(json.dumps({'number':42,'title':'A test PR','url':'https://github.com/fixture/app/pull/42','state':'OPEN','isDraft':False,'headRefName':args[2],'headRefOid':'remote-sha','baseRefName':'main','reviewDecision':'','statusCheckRollup':[{'name':'Build','status':'COMPLETED','conclusion':'SUCCESS','detailsUrl':'https://github.com/fixture/app/actions/runs/1'},{'context':'External','state':'PENDING','targetUrl':''}]}))
        elif args[:2] == ['run','list']:
            print(json.dumps([{'databaseId':1,'displayTitle':'CI','workflowName':'Build','status':'completed','conclusion':'success','headSha':args[args.index('--commit')+1],'url':'https://github.com/fixture/app/actions/runs/1'}]))
        else: sys.exit(2)
        """#
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let remote = try await InspectorService.github(at: repository.path, branch: GitBranch(name: "feature/test", isDetached: false), headSHA: "local-sha", executable: fake)
        try require(remote.changeRequest?.number == 42 && remote.changeRequest?.statusCheckRollup?.count == 2 && remote.runs.first?.headSha == "local-sha", "Decode PR checks, legacy status contexts and commit-filtered runs")
        let noPR = try await InspectorService.github(at: repository.path, branch: GitBranch(name: "none", isDetached: false), headSHA: nil, executable: fake)
        try require(noPR.changeRequest == nil && noPR.changeRequestError == nil, "No PR is a valid empty state")
        let offline = try await InspectorService.github(at: repository.path, branch: GitBranch(name: "offline", isDetached: false), headSHA: nil, executable: fake)
        try require(offline.changeRequestError?.contains("connecting") == true, "Network failure is not reported as no PR")
        let calls = try String(contentsOf: fake.withExtension("calls"), encoding: .utf8)
        try require(calls.contains("--commit") && calls.contains("local-sha"), "gh Actions query filters current commit")
        print("PASS gh JSON decoding, commit filtering, no PR and network failures")

        let hosts = ["git@gitlab.com:group/app.git", "https://gitlab.example.org/group/app", "ssh://git@gitlab.internal:2222/app.git",
                     "git@gitlab.com:app.git", "file://gitlab.internal/srv/app.git",
                     "git@github.com:owner/app.git", "https://github.com/owner/app.git"].map(GitHosting.init(remoteURL:))
        try require(hosts == [.gitlab, .gitlab, .gitlab, .gitlab, .gitlab, .github, .github],
                    "Detect GitLab and GitHub from the host of remote URLs, even those with no web address")
        _ = try await GitService.run(["remote", "add", "origin", "git@gitlab.com:fixture/app.git"], at: repository.path)
        let detected = await InspectorService.hosting(at: repository.path)
        _ = try await GitService.run(["remote", "remove", "origin"], at: repository.path)
        try require(detected == .gitlab, "Read the hosting from the origin remote")
        try testChangeRequestPages()

        let fakeGlab = root.appendingPathComponent("fake-glab")
        let glabScript = #"""
        #!/usr/bin/python3
        import sys,json,pathlib
        args=sys.argv[1:]
        with open(pathlib.Path(__file__).with_suffix('.calls'),'a') as f: f.write(json.dumps(args)+'\n')
        endpoint=args[1] if args[:1]==['api'] else ''
        if endpoint=='projects/:id':
            print(json.dumps({'path_with_namespace':'fixture/app','web_url':'https://gitlab.com/fixture/app','description':''}))
        elif endpoint.startswith('projects/:id/merge_requests?'):
            if 'source_branch=none' in endpoint: print('[]')
            elif 'source_branch=offline' in endpoint: print('dial tcp: lookup gitlab.com: no such host',file=sys.stderr);sys.exit(1)
            else: print(json.dumps([{'iid':6,'title':'Old','web_url':'u','state':'merged','source_branch':'feature/test','target_branch':'main'},
                                    {'iid':7,'title':'A test MR','web_url':'https://gitlab.com/fixture/app/-/merge_requests/7','state':'opened','source_branch':'feature/test','target_branch':'main'}]))
        elif endpoint=='projects/:id/merge_requests/7':
            print(json.dumps({'iid':7,'title':'A test MR','web_url':'https://gitlab.com/fixture/app/-/merge_requests/7','state':'opened','draft':True,'source_branch':'feature/test','target_branch':'main','sha':'remote-sha','head_pipeline':{'id':99,'project_id':5}}))
        elif endpoint.startswith('projects/5/pipelines/99/jobs'):
            print(json.dumps([{'name':'unit','stage':'test','status':'failed','web_url':'https://gitlab.com/fixture/app/-/jobs/1'},{'name':'lint','stage':'test','status':'running','web_url':None}]))
        elif endpoint.startswith('projects/:id/pipelines?sha='):
            print(json.dumps([{'id':99,'iid':12,'ref':'feature/test','status':'success','sha':endpoint.split('sha=')[1].split('&')[0],'web_url':'https://gitlab.com/fixture/app/-/pipelines/99'}]))
        else: sys.exit(2)
        """#
        try glabScript.write(to: fakeGlab, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeGlab.path)
        let gitlab = try await InspectorService.gitlab(at: repository.path, branch: GitBranch(name: "feature/test", isDetached: false), headSHA: "local-sha", executable: fakeGlab)
        let checks = gitlab.changeRequest?.statusCheckRollup ?? []
        try require(gitlab.hosting == .gitlab && gitlab.repository.nameWithOwner == "fixture/app" && gitlab.repository.description == nil, "Decode the GitLab project")
        try require(gitlab.changeRequest?.number == 7 && gitlab.changeRequest?.isDraft == true && gitlab.changeRequest?.state == "OPEN"
                    && gitlab.changeRequest?.headRefOid == "remote-sha", "Prefer the open merge request of the branch")
        try require(checks.map(\.title) == ["test · unit", "test · lint"] && checks.map(\.result) == ["FAILURE", "running"], "Map pipeline jobs to checks")
        try require(gitlab.runs.first?.headSha == "local-sha" && gitlab.runs.first?.result == "SUCCESS" && gitlab.runs.first?.workflowName == "Pipeline #12", "Decode commit pipelines")
        let noMR = try await InspectorService.gitlab(at: repository.path, branch: GitBranch(name: "none", isDetached: false), headSHA: nil, executable: fakeGlab)
        try require(noMR.changeRequest == nil && noMR.changeRequestError == nil, "No merge request is a valid empty state")
        let offlineMR = try await InspectorService.gitlab(at: repository.path, branch: GitBranch(name: "offline", isDetached: false), headSHA: nil, executable: fakeGlab)
        try require(offlineMR.changeRequestError?.contains("no such host") == true, "Network failure is not reported as no merge request")
        _ = try await InspectorService.gitlab(at: repository.path, branch: GitBranch(name: "feature/a&b", isDetached: false), headSHA: nil, executable: fakeGlab)
        let glabCalls = try String(contentsOf: fakeGlab.withExtension("calls"), encoding: .utf8)
        try require(glabCalls.contains("source_branch=feature%2Fa%26b"), "Branch names are encoded in GitLab queries")
        print("PASS GitLab hosting detection, glab JSON decoding, no MR and network failures")

        do {
            _ = try await ReadCommand.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], at: root.path, timeout: 0.1)
            throw WorkspaceError(message: "FAIL: timeout missing")
        } catch let error as ReadCommandError { try require(error.message.contains("in time"), "Timed out query reports error") }
        let task = Task { try await ReadCommand.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], at: root.path) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; throw WorkspaceError(message: "FAIL: cancellation missing") }
        catch is CancellationError {}
        do {
            _ = try await ReadCommand.run(URL(fileURLWithPath: "/bin/cat"), [big.path], at: root.path, limit: 32)
            throw WorkspaceError(message: "FAIL: output limit missing")
        } catch is ReadCommandError {}
        let start = Date()
        do {
            _ = try await ReadCommand.run(URL(fileURLWithPath: "/usr/bin/yes"), [], at: root.path, timeout: 5, limit: 1024)
            throw WorkspaceError(message: "FAIL: running output limit missing")
        } catch let error as ReadCommandError { try require(error.message.contains("limit"), "Stop excessive output while query runs") }
        try require(Date().timeIntervalSince(start) < 2, "Output termination should precede timeout")
        print("PASS query cancellation, timeout and live output limit")
    }

    private static func porcelainEntry(_ kind: String, _ codes: String, _ fields: Int, _ path: String) -> String {
        ([kind, codes] + Array(repeating: "x", count: fields - 2) + [path]).joined(separator: " ")
    }

    private static func changeTree() throws {
        let require = CoreTests.require
        func change(_ path: String, _ x: String = " ", _ y: String = "M") -> GitChange {
            GitChange(path: path, originalPath: nil, indexStatus: x, worktreeStatus: y)
        }
        let tree = GitChangeFolder(changes: [change("Sources/App/Views/B.swift"), change("README.md"), change("Sources/App/Views/A.swift"),
                                             change("Tests/unit/file10.swift"), change("Tests/unit/file2.swift"), change("Tests/z.swift"),
                                             change("a/b/c/d.txt")])
        try require(tree.path.isEmpty && tree.files.map(\.path) == ["README.md"] && tree.folders.map(\.name) == ["a/b/c", "Sources/App/Views", "Tests"],
                    "Root files stay at the top and single-child folder chains are compacted")
        let views = tree.folders[1], tests = tree.folders[2]
        try require(views.path == "Sources/App/Views" && views.folders.isEmpty && views.files.map(\.name) == ["A.swift", "B.swift"],
                    "Compacted folders keep their full path and sorted files")
        try require(tests.files.map(\.name) == ["z.swift"] && tests.folders.map(\.path) == ["Tests/unit"]
                    && tests.folders[0].files.map(\.name) == ["file2.swift", "file10.swift"],
                    "A folder with files is not compacted and names sort naturally")
        try require(GitChangeFolder(changes: []).count == 0 && GitChangeOutline(changes: []) == .empty && GitChangeOutline.empty.isEmpty && tree.count == 7,
                    "No changes build an empty tree and counts include nested files")
        let outline = GitChangeOutline(changes: [change("Sources/App/Views/B.swift"), change("README.md"), change("Sources/App/Views/A.swift"),
                                                 change("Tests/unit/file10.swift"), change("Tests/unit/file2.swift"), change("Tests/z.swift"),
                                                 change("a/b/c/d.txt")])
        let rows = outline.rows(collapsing: [])
        try require(rows == tree.rows && outline.count == 7 && rows.count == 11 && rows.map(\.depth) == [0, 1, 0, 1, 1, 0, 1, 2, 2, 1, 0]
                    && rows.first?.id == .folder("a/b/c") && rows.last?.id == .file("README.md"),
                    "Expanded folders flatten into rows with their depth, folders before files")
        let collapsedRows = outline.rows(collapsing: ["Tests", "a/b/c"])
        try require(collapsedRows.map(\.id) == [.folder("a/b/c"), .folder("Sources/App/Views"), .file("Sources/App/Views/A.swift"),
                                                .file("Sources/App/Views/B.swift"), .folder("Tests"), .file("README.md")],
                    "Collapsed folders hide their rows but keep their own row")
        try require(outline.rows(collapsing: ["Tests/unit"]).map(\.id).suffix(4) == [.folder("Tests"), .folder("Tests/unit"), .file("Tests/z.swift"), .file("README.md")],
                    "Collapsing a nested folder keeps the files of its parent")

        let both = change("both", "M", "M"), staged = change("staged", "A", " "), untracked = change("new", "?", "?"),
            conflict = change("conflict", "U", "U"), deleted = change("gone", " ", "D")
        let snapshot = LocalGitSnapshot(root: "/r", branch: GitBranch(name: "main"), headSHA: "abc", changes: [both, staged, untracked, conflict, deleted],
                                        tracking: GitTracking(upstream: "origin/main", ahead: 2, tracksSameBranch: true))
        try require(snapshot.stagedChanges == [both, staged] && snapshot.unstagedChanges == [both, untracked, conflict, deleted],
                    "Partially staged files appear in both sections, conflicts and untracked files only in Changes")
        try require(GitChangeScope.staged.kind(of: both) == .modified && GitChangeScope.staged.kind(of: staged) == .added
                    && GitChangeScope.unstaged.kind(of: untracked) == .untracked && GitChangeScope.unstaged.kind(of: conflict) == .conflicted
                    && GitChangeScope.unstaged.kind(of: deleted) == .deleted, "Each section shows its own status column")
        let renamed = GitChange(path: "new name", originalPath: "old name", indexStatus: "R", worktreeStatus: "M")
        try require(GitChangeScope.staged.action(for: renamed) == .unstage(["new name", "old name"])
                    && GitChangeScope.unstaged.action(for: renamed) == .stage(["new name"])
                    && GitChangeScope.branch(ComparisonBranch(reference: "refs/heads/main")).action(for: renamed) == nil,
                    "Unstaging a rename restores both paths and branch rows have no action")

        let header = { (lines: [String]) in GitStatus.parse(Data((lines + [porcelainEntry("1", ".M", 8, "file"), ""]).joined(separator: "\0").utf8)) }
        let oid = "# branch.oid abc"
        try require(header([oid, "# branch.head main", "# branch.upstream origin/main", "# branch.ab +2 -1"]).tracking == GitTracking(upstream: "origin/main", ahead: 2)
                    && header([oid, "# branch.head feature/x", "# branch.upstream origin/feature/x", "# branch.ab +0 -0"]).tracking == GitTracking(upstream: "origin/feature/x", ahead: 0)
                    && header([oid, "# branch.head main"]).tracking == GitTracking(upstream: nil)
                    && header([oid, "# branch.head main", "# branch.upstream origin/main"]).tracking == GitTracking(upstream: nil, goneUpstream: "origin/main")
                    && header(["# branch.oid (initial)", "# branch.head main", "# branch.upstream origin/main"]) == GitStatus(changes: [GitChange(path: "file", originalPath: nil, indexStatus: " ", worktreeStatus: "M")])
                    && header([oid, "# branch.head (detached)"]).tracking == nil && header([oid, "# branch.head (detached)"]).headSHA == "abc"
                    && header([]).tracking == nil && header([]).changes.map(\.path) == ["file"],
                    "Parse the porcelain v2 branch headers, never as changes")
        try require(snapshot.push == .push && GitTracking(upstream: "origin/main", tracksSameBranch: true).push(branch: "main") == nil
                    && GitTracking(upstream: nil).push(branch: "main") == nil
                    && GitTracking(upstream: nil, remote: "fork").push(branch: "main") == .publish(remote: "fork", branch: "main")
                    && LocalGitSnapshot(root: "/r", branch: GitBranch(name: "abc", isDetached: true), headSHA: "abc", changes: [],
                                        tracking: GitTracking(upstream: nil)).push == nil
                    && LocalGitSnapshot(root: "/r", branch: GitBranch(name: "main"), headSHA: nil, changes: [], tracking: GitTracking(upstream: nil)).push == nil,
                    "Offer push for commits ahead or a branch without upstream that has a remote")
        let gone = { (state: BranchMergeState?) in GitTracking(upstream: nil, remote: "origin", goneUpstream: "origin/main", mergeState: state) }
        try require([BranchMergeState.merged, .unmerged, .unknown, nil].allSatisfy { gone($0).push(branch: "main") == nil },
                    "A deleted remote branch never offers Push or Publish as the main action")
        try require(gone(.merged).republish(branch: "main") == nil && gone(nil).republish(branch: "main") == nil
                    && gone(.unmerged).republish(branch: "main") == .republish(remote: "origin", branch: "main")
                    && gone(.unknown).republish(branch: "main") == .republish(remote: "origin", branch: "main")
                    && GitTracking(upstream: nil, remote: "origin").republish(branch: "main") == nil
                    && LocalGitSnapshot(root: "/r", branch: GitBranch(name: "main"), headSHA: "abc", changes: [], tracking: gone(.unmerged)).republish
                        == .republish(remote: "origin", branch: "main"),
                    "Publish Again only recreates a deleted remote branch whose work isn't known to be merged")
        try require(GitAction.republish(remote: "origin", branch: "main").arguments == GitAction.publish(remote: "origin", branch: "main").arguments
                    && String(localized: GitAction.republish(remote: "origin", branch: "main").title) == "Publish Again"
                    && String(localized: GitAction.republish(remote: "origin", branch: "main").help).contains("origin/main"),
                    "Publish Again pushes like Publish and says which remote branch it recreates")
        var prompts = AgentPrompts()
        prompts.changeRequest = "Open the PR."
        let teamRemote = LocalGitSnapshot(root: "/r", branch: GitBranch(name: "feature"), headSHA: "abc", changes: [],
                                          remoteWebAddresses: ["team/upstream": RemoteWebAddress(remoteURL: "git@github.com:team/app.git")!])
        try require(AgentRequest.changeRequest(baseBranch: teamRemote.hostedName(of: ComparisonBranch(reference: "refs/remotes/team/upstream/develop")))
                        .prompt(from: prompts) == "Open the PR.\n\nBase branch: develop"
                    && teamRemote.hostedName(of: ComparisonBranch(reference: "refs/remotes/origin/release/1.0")) == "release/1.0"
                    && teamRemote.hostedName(of: ComparisonBranch(reference: "refs/heads/release/1.0")) == "release/1.0"
                    && AgentRequest.commit.prompt(from: prompts) == prompts.commit,
                    "Asking the agent for a change request names the base chosen in Branch Comparison, without its remote, after the user's prompt")
        try require(String(localized: GitActionFailure(action: .stage(["docs/README.md"]), error: "boom").message) == "Couldn’t stage README.md: boom"
                    && String(localized: GitAction.stage(["a"]).accessibilityLabel(for: "a.txt")) == "Stage a.txt"
                    && String(localized: GitAction.stageAll.accessibilityLabel(for: "a.txt")) == "Stage All"
                    && GitAction.stage(["a"]).retries(.stage(["a"])) && !GitAction.stage(["b"]).retries(.stage(["a"]))
                    && !GitAction.stageAll.retries(.stage(["a"])) && GitAction.commit(title: "b", message: "").retries(.commit(title: "a", message: "")),
                    "A Git failure names its action and only the same action retried clears it")
        try require(LocalGitSnapshot(root: "/r", branch: nil, headSHA: nil, changes: [], containsStagedChanges: true).hasStagedChanges
                    && !LocalGitSnapshot(root: "/r", branch: nil, headSHA: nil, changes: [], containsStagedChanges: false).hasStagedChanges
                    && LocalGitSnapshot(root: "/r", branch: nil, headSHA: nil,
                                        changes: [GitChange(path: "a", originalPath: nil, indexStatus: "M", worktreeStatus: " ")]).hasStagedChanges,
                    "Staged files beyond the listed ones still count as staged")
        let foreign = GitTracking(upstream: "origin/main", ahead: 3, remote: "origin", tracksSameBranch: false)
        try require(!foreign.isPublished && !foreign.hasUnpushedCommits && foreign.push(branch: "feature") == .publish(remote: "origin", branch: "feature")
                    && GitTracking(upstream: "origin/main", ahead: 3).push(branch: "feature") == nil
                    && GitTracking(upstream: "origin/feature", ahead: 1, tracksSameBranch: true).hasUnpushedCommits
                    && !GitTracking(upstream: "origin/feature", tracksSameBranch: true).hasUnpushedCommits
                    && !GitTracking(upstream: nil, tracksSameBranch: true).isPublished,
                    "A branch tracking a differently named upstream is published to its own name, never pushed onto the upstream")
        func remotes(_ entries: [(String, String)]) -> GitRemoteConfiguration {
            GitRemoteConfiguration(entries: entries.map { (key: $0.0, value: $0.1) })
        }
        let forkAndOrigin = remotes([("remote.fork.url", "git@github.com:me/app.git"), ("remote.origin.url", "git@gitlab.com:team/app.git")])
        try require(remotes([]).pushRemote(for: "main") == nil && remotes([]).primaryURL == nil
                    && remotes([("remote.fork.url", "u")]).pushRemote(for: "main") == "fork"
                    && remotes([("remote.fork.url", "u"), ("remote.upstream.url", "v")]).pushRemote(for: "main") == nil
                    && forkAndOrigin.pushRemote(for: "main") == "origin" && forkAndOrigin.primaryURL == "git@gitlab.com:team/app.git"
                    && remotes([("remote.fork.url", "u"), ("remote.origin.url", "v"), ("remote.pushdefault", "fork")]).pushRemote(for: "main") == "fork"
                    && remotes([("remote.fork.url", "u"), ("remote.origin.url", "v"), ("branch.Feature/x.remote", "fork")]).pushRemote(for: "Feature/x") == "fork"
                    && remotes([("remote.fork.url", "u"), ("remote.origin.url", "v"), ("branch.main.remote", "fork"), ("branch.main.pushremote", "origin")]).pushRemote(for: "main") == "origin"
                    && remotes([("remote.origin.url", "v"), ("branch.main.remote", "gone")]).pushRemote(for: "main") == "origin"
                    && remotes([("remote.--upload-pack=x.url", "v")]).pushRemote(for: "main") == nil,
                    "Publish to the configured push remote, else origin, else the only remote, never an option-like name")
        let optionLike = remotes([("remote.--upload-pack=x.url", "v"), ("branch.fix.remote", "--upload-pack=x"), ("branch.fix.merge", "refs/heads/bugfix")])
        try require(optionLike.upstream(of: "fix") == nil && optionLike.pushRemote(for: "fix") == nil
                    && remotes([("remote.origin.url", "v"), ("branch.fix.remote", "origin"), ("branch.fix.merge", "refs/heads/bugfix")]).upstream(of: "fix")
                        == GitUpstream(remote: "origin", branch: "bugfix")
                    && GitAction.pushUpstream(GitUpstream(remote: "-x", branch: "b")).arguments == ["push", "--", "-x", "HEAD:refs/heads/b"],
                    "An option-like remote is never an upstream, and remotes are passed after --")
        let tracked = { (remote: String, merge: String) in
            remotes([("remote.origin.url", "v"), ("branch.Feature/x.remote", remote), ("branch.Feature/x.merge", merge)]).tracksSameBranch("Feature/x")
        }
        try require(tracked("origin", "refs/heads/Feature/x") && !tracked("origin", "refs/heads/main") && !tracked(".", "refs/heads/Feature/x")
                    && !tracked("gone", "refs/heads/Feature/x") && !remotes([("remote.origin.url", "v")]).tracksSameBranch("main"),
                    "Only a same-named branch on a configured remote counts as the branch's published upstream")

        try require(GitAction.commit(title: "  Title ", description: "\n") == .commit(title: "Title", message: "")
                    && GitAction.commit(title: " ", description: "Body") == nil
                    && GitAction.commit(title: "T", message: "").arguments == ["commit", "--message", "T"]
                    && GitAction.commit(title: "T", message: "$(rm -rf /)").arguments == ["commit", "--message", "T", "--message", "$(rm -rf /)"]
                    && GitAction.publish(remote: "fork", branch: "feature").arguments == ["push", "--set-upstream", "--", "fork", "HEAD:refs/heads/feature"]
                    && GitAction.push.arguments == ["push"] && GitAction.publish(remote: "o", branch: "b").updatesRemote
                    && GitAction.unstageAll.arguments == ["reset", "--quiet", "--", "."]
                    && GitAction.stage(["-rf"]).arguments == ["--literal-pathspecs", "add", "--", "-rf"],
                    "Git actions pass titles and paths as plain arguments")
        print("PASS change tree, sections, branch tracking and git actions")
    }

    private static func workingTreeActions(root: URL) async throws {
        let require = CoreTests.require
        let repository = root.appendingPathComponent("actions repository")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("src/app"), withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        _ = try await GitService.run(["config", "user.name", "Heka Tests"], at: repository.path)
        _ = try await GitService.run(["config", "user.email", "tests@example.invalid"], at: repository.path)
        try "one\n".write(to: repository.appendingPathComponent("src/app/one.txt"), atomically: true, encoding: .utf8)
        try "two\n".write(to: repository.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stage(["src/app/one.txt"]), at: repository.path)
        var local = try await InspectorService.localGit(at: repository.path)
        try require(local.hasStagedChanges && local.stagedChanges.map(\.path) == ["src/app/one.txt"] && local.unstagedChanges.map(\.path) == ["two.txt"] && local.push == nil,
                    "Stage one file on an unborn branch")
        guard let staged = local.stagedChanges.first else { fatalError("Missing staged change") }
        let stagedDiff = try await InspectorService.diff(staged, at: repository.path, including: [.staged])
        try require(stagedDiff.sections.map(\.kind) == [.staged], "Staged rows preview only the index diff")
        try await InspectorService.perform(.unstage(["src/app/one.txt"]), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.stagedChanges.isEmpty && !local.hasStagedChanges && local.unstagedChanges.count == 2, "Unstage works before the first commit")
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.unstageAll, at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.stagedChanges.isEmpty && local.unstagedChanges.count == 2, "Unstage All works before the first commit")
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "First", message: "Body"), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        let log = try await GitService.run(["log", "-1", "--format=%B"], at: repository.path)
        try require(local.changes.isEmpty && log == "First\n\nBody" && local.tracking == GitTracking(upstream: nil, tracksSameBranch: false) && local.push == nil,
                    "Commit title and description, and hide Push without a remote")
        _ = try await GitService.run(["remote", "add", "fork", "git@github.com:me/app.git"], at: repository.path)
        let onlyFork = try await InspectorService.localGit(at: repository.path).push
        _ = try await GitService.run(["remote", "add", "origin", "git@github.com:team/app.git"], at: repository.path)
        let withOrigin = try await InspectorService.localGit(at: repository.path).push
        _ = try await GitService.run(["config", "remote.pushDefault", "fork"], at: repository.path)
        let pushDefault = try await InspectorService.localGit(at: repository.path).push
        try require(onlyFork == .publish(remote: "fork", branch: "main") && withOrigin == .publish(remote: "origin", branch: "main")
                    && pushDefault == .publish(remote: "fork", branch: "main"), "Publish the branch to the remote Git would push to")
        try "changed\n".write(to: repository.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.unstageAll, at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.stagedChanges.isEmpty && local.unstagedChanges.map(\.path) == ["two.txt"], "Stage All and Unstage All")
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Second", message: ""), at: repository.path)
        _ = try await GitService.run(["switch", "-q", "-c", "side", "HEAD~1"], at: repository.path)
        try "side\n".write(to: repository.appendingPathComponent("side.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Side", message: ""), at: repository.path)
        try "dirty\n".write(to: repository.appendingPathComponent("side.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["merge", "--no-ff", "--no-commit", "main"], at: repository.path)
        let mergeHead = repository.appendingPathComponent(".git/MERGE_HEAD")
        local = try await InspectorService.localGit(at: repository.path)
        try require(FileManager.default.fileExists(atPath: mergeHead.path) && local.stagedChanges.map(\.path) == ["two.txt"],
                    "The fixture merge is in progress with staged changes")
        try await InspectorService.perform(.unstageAll, at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(FileManager.default.fileExists(atPath: mergeHead.path) && local.stagedChanges.isEmpty
                    && Set(local.unstagedChanges.map(\.path)) == ["side.txt", "two.txt"],
                    "Unstage All keeps the merge in progress")
        print("PASS stage, unstage and commit")
    }

    private static func publishing(root: URL) async throws {
        let require = CoreTests.require
        let remote = root.appendingPathComponent("publishing remote.git")
        let repository = root.appendingPathComponent("publishing repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "--bare", "-b", "main", remote.path], at: root.path)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        _ = try await GitService.run(["config", "user.name", "Heka Tests"], at: repository.path)
        _ = try await GitService.run(["config", "user.email", "tests@example.invalid"], at: repository.path)
        _ = try await GitService.run(["config", "push.default", "upstream"], at: repository.path)
        _ = try await GitService.run(["remote", "add", "origin", remote.path], at: repository.path)
        try "base\n".write(to: repository.appendingPathComponent("base.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Base", message: ""), at: repository.path)
        try await InspectorService.perform(.publish(remote: "origin", branch: "main"), at: repository.path)
        let mainHead = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        var local = try await InspectorService.localGit(at: repository.path)
        try require(local.tracking?.isPublished == true && local.push == nil, "Publishing main tracks origin/main")
        _ = try await GitService.run(["checkout", "-q", "-b", "feature", "origin/main"], at: repository.path)
        try "feature\n".write(to: repository.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Feature", message: ""), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.tracking?.upstream == "origin/main" && local.tracking?.ahead == 1 && local.tracking?.isPublished == false
                    && local.push == .publish(remote: "origin", branch: "feature"),
                    "A branch created from origin/main is published under its own name")
        guard let push = local.push else { fatalError("Missing push action") }
        try await InspectorService.perform(push, at: repository.path)
        let remoteMain = try await GitService.run(["rev-parse", "main"], at: remote.path)
        let remoteFeature = try await GitService.run(["rev-parse", "feature"], at: remote.path)
        let featureHead = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(remoteMain == mainHead && remoteFeature == featureHead && local.tracking?.upstream == "origin/feature"
                    && local.tracking?.isPublished == true && local.push == nil,
                    "Pushing leaves origin/main untouched and makes origin/feature the upstream")
        try "more\n".write(to: repository.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "More", message: ""), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.push == .push && local.tracking?.hasUnpushedCommits == true, "Later commits use a plain push to the same-named upstream")
        _ = try await GitService.run(["push", "-q", "origin", "--delete", "feature"], at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.tracking?.goneUpstream == "origin/feature" && local.tracking?.upstream == nil
                        && local.push == nil && local.republish == .republish(remote: "origin", branch: "feature"),
                    "A deleted upstream with commits outside the main branch can be published again")
        _ = try await GitService.run(["push", "-q", "origin", "HEAD:refs/heads/main"], at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.tracking?.goneUpstream == "origin/feature" && local.push == nil && local.republish == nil,
                    "A deleted upstream whose commits are merged into the main branch is never recreated")
        _ = try await GitService.run(["push", "-q", "origin", "HEAD:refs/heads/bugfix/fix-123"], at: repository.path)
        _ = try await GitService.run(["checkout", "-q", "-b", "fix", "--track", "origin/bugfix/fix-123"], at: repository.path)
        try "fix\n".write(to: repository.appendingPathComponent("fix.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Fix", message: ""), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        let fixUpstream = GitUpstream(remote: "origin", branch: "bugfix/fix-123")
        try require(local.tracking?.upstream == "origin/bugfix/fix-123" && local.tracking?.isPublished == true
                        && local.tracking?.remoteBranch(for: "fix") == "bugfix/fix-123" && local.push == .pushUpstream(fixUpstream),
                    "A branch tracking a differently named branch that isn't the main branch pushes to its upstream")
        try await InspectorService.perform(.pushUpstream(fixUpstream), at: repository.path)
        let remoteFix = try await GitService.run(["rev-parse", "bugfix/fix-123"], at: remote.path)
        let fixHead = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        let strayFix = try? await GitService.run(["rev-parse", "--verify", "--quiet", "refs/heads/fix"], at: remote.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(remoteFix == fixHead && strayFix == nil && local.tracking?.upstream == "origin/bugfix/fix-123" && local.push == nil,
                    "Pushing to a differently named upstream keeps it and creates no branch under the local name")
        _ = try await GitService.run(["checkout", "-q", "--track", "-b", "local-track", "main"], at: repository.path)
        try "local\n".write(to: repository.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Local", message: ""), at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        let localRemote = try await GitService.run(["config", "branch.local-track.remote"], at: repository.path)
        let localMerge = try await GitService.run(["config", "branch.local-track.merge"], at: repository.path)
        let publishLocal = GitAction.publish(remote: "origin", branch: "local-track")
        try require(local.tracking?.upstream == "main" && local.tracking?.isPublished == false && !(local.tracking?.hasUnpushedCommits ?? true)
                        && local.push == publishLocal && String(localized: publishLocal.title) == "Publish"
                        && String(localized: publishLocal.help) == "Push this branch to a new origin/local-track branch and track it"
                        && localRemote == "." && localMerge == "refs/heads/main",
                    "A branch tracking a local branch is unpublished, offers an explicit Publish to origin and keeps its upstream until then")
        try await InspectorService.perform(publishLocal, at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.tracking?.upstream == "origin/local-track" && local.tracking?.isPublished == true && local.push == nil,
                    "Publishing a branch tracking a local branch creates and tracks origin/<branch>")
        _ = try await GitService.run(["checkout", "-q", "--detach"], at: repository.path)
        let detachedHead = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(local.branch?.isDetached == true && local.headSHA == detachedHead && local.tracking == nil && local.push == nil,
                    "A detached HEAD keeps its commit and offers no push")
        let fork = root.appendingPathComponent("publishing fork.git")
        _ = try await GitService.run(["init", "-q", "--bare", "-b", "main", fork.path], at: root.path)
        _ = try await GitService.run(["remote", "add", "fork", fork.path], at: repository.path)
        _ = try await GitService.run(["config", "remote.pushdefault", "fork"], at: repository.path)
        _ = try await GitService.run(["checkout", "-q", "-b", "feat", "origin/main"], at: repository.path)
        try "feat\n".write(to: repository.appendingPathComponent("feat.txt"), atomically: true, encoding: .utf8)
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Feat", message: ""), at: repository.path)
        _ = try await GitService.run(["push", "-q", "--set-upstream", "origin", "HEAD:refs/heads/feature-x"], at: repository.path)
        _ = try await GitService.run(["push", "-q", "origin", "--delete", "feature-x"], at: repository.path)
        local = try await InspectorService.localGit(at: repository.path)
        let republishFeat = GitAction.republish(remote: "origin", branch: "feature-x")
        try require(local.tracking?.goneUpstream == "origin/feature-x" && local.republish == republishFeat
                        && String(localized: republishFeat.help).contains("origin/feature-x"),
                    "Publish Again recreates the deleted upstream, not the local name on the push remote")
        try await InspectorService.perform(republishFeat, at: repository.path)
        let remoteFeat = try await GitService.run(["rev-parse", "feature-x"], at: remote.path)
        let featHead = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        let forkFeat = try? await GitService.run(["rev-parse", "--verify", "--quiet", "refs/heads/feat"], at: fork.path)
        local = try await InspectorService.localGit(at: repository.path)
        try require(remoteFeat == featHead && forkFeat == nil && local.tracking?.upstream == "origin/feature-x" && local.tracking?.goneUpstream == nil,
                    "Publishing again pushes to the configured upstream and keeps tracking it")
        print("PASS publish a branch whose upstream has another name")
    }

    private static func porcelainStatus(root: URL) async throws {
        let require = CoreTests.require
        let repository = root.appendingPathComponent("porcelain repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        _ = try await GitService.run(["config", "user.name", "Heka Tests"], at: repository.path)
        _ = try await GitService.run(["config", "user.email", "tests@example.invalid"], at: repository.path)
        _ = try await GitService.run(["config", "status.renames", "copies"], at: repository.path)
        let lines = (1...20).map { "line \($0)\n" }.joined()
        for name in ["source.txt", "old name.txt", "conflict.txt", "removed.txt"] {
            try (name + "\n" + lines).write(to: repository.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try await InspectorService.perform(.stageAll, at: repository.path)
        try await InspectorService.perform(.commit(title: "Base", message: ""), at: repository.path)
        _ = try await GitService.run(["switch", "-q", "-c", "other"], at: repository.path)
        try "other\n".write(to: repository.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["commit", "-q", "-am", "Other"], at: repository.path)
        _ = try await GitService.run(["switch", "-q", "main"], at: repository.path)
        try "main\n".write(to: repository.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["commit", "-q", "-am", "Main"], at: repository.path)
        _ = try? await GitService.run(["merge", "-q", "other"], at: repository.path)
        _ = try await GitService.run(["mv", "old name.txt", "new\tname.txt"], at: repository.path)
        try ("source.txt\n" + lines + "more\n").write(to: repository.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
        try ("source.txt\n" + lines).write(to: repository.appendingPathComponent("café copy.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "--", "source.txt", "café copy.txt"], at: repository.path)
        try "edited\n".write(to: repository.appendingPathComponent("café copy.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repository.appendingPathComponent("removed.txt"))
        try "new\n".write(to: repository.appendingPathComponent(" untracked file"), atomically: true, encoding: .utf8)
        let local = try await InspectorService.localGit(at: repository.path)
        let changes = Dictionary(uniqueKeysWithValues: local.changes.map { ($0.path, $0) })
        let head = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        try require(local.headSHA == head && local.tracking == GitTracking(upstream: nil, tracksSameBranch: false)
                    && changes["new\tname.txt"]?.originalPath == "old name.txt" && changes["new\tname.txt"]?.status == "R"
                    && changes["café copy.txt"]?.originalPath == "source.txt" && changes["café copy.txt"]?.status == "CM"
                    && changes["source.txt"]?.status == "M" && changes["source.txt"]?.isStaged == true
                    && changes["conflict.txt"]?.isConflicted == true && changes["conflict.txt"]?.status == "UU"
                    && changes["removed.txt"]?.status == "D" && changes["removed.txt"]?.isUnstaged == true && changes["removed.txt"]?.isStaged == false
                    && changes[" untracked file"]?.isUntracked == true && local.changes.count == 6,
                    "Real porcelain v2 status reports renames, copies, conflicts, deletions, untracked files and HEAD")
        print("PASS porcelain v2 status on a real repository")
    }

    private static func gitRootCache(root: URL) async throws {
        let require = CoreTests.require
        let repository = root.appendingPathComponent("root cache repository")
        let nested = repository.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        let resolutions = ResolutionCount()
        let cache = GitRootCache { path in
            await resolutions.increment()
            return try await GitRootCache.topLevel(at: path)
        }
        let first = try await cache.root(at: nested.path)
        let second = try await cache.location(at: nested.path)
        let afterRepeat = await resolutions.value
        try require(first == WorkspacePath.canonical(repository) && second.root == first && second.repository?.root.path == first
                        && second.repository?.branch.name == "main" && afterRepeat == 1,
                    "The repository root of an inspected path is resolved once while its repository stays in place, with its repository")
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: nested.path)
        let inner = try await cache.root(at: nested.path)
        let afterNested = await resolutions.value
        try require(inner == WorkspacePath.canonical(nested) && afterNested == 2, "A repository created inside the inspected path replaces the cached root")
        _ = try await cache.root(at: repository.path)
        await cache.prune(keepingPathsIn: [nested.path])
        _ = try await cache.root(at: nested.path)
        let keptAfterPrune = await resolutions.value
        _ = try await cache.root(at: repository.path)
        let droppedAfterPrune = await resolutions.value
        try require(keptAfterPrune == 3 && droppedAfterPrune == 4, "Pruning keeps the roots of current worktrees and drops the others")
        try FileManager.default.removeItem(at: nested.appendingPathComponent(".git"))
        try FileManager.default.removeItem(at: repository.appendingPathComponent(".git"))
        do {
            _ = try await cache.root(at: nested.path)
            throw WorkspaceError(message: "FAIL: a removed repository still has a root")
        } catch is ReadCommandError {}
        let afterRemoval = await resolutions.value
        try require(afterRemoval == 5, "A removed repository is resolved by Git again")
        print("PASS repository roots are cached per inspected path")
        try await branchMergeCache(root: root)
    }

    private static func branchMergeCache(root: URL) async throws {
        let require = CoreTests.require
        let repository = root.appendingPathComponent("merge cache repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try await GitService.run(["init", "-q", "-b", "main"], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=Heka Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Base"],
                                     at: repository.path)
        _ = try await GitService.run(["checkout", "-q", "-b", "topic"], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=Heka Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "--allow-empty", "-m", "Work"],
                                     at: repository.path)
        let head = try await GitService.run(["rev-parse", "HEAD"], at: repository.path)
        let checks = ResolutionCount()
        let cache = BranchMergeCache(targets: { try await GitService.mergeTargets(among: $0, at: $1) },
                                     merged: { branch, targets, path in
                                         await checks.increment()
                                         return try await GitService.isMerged(branch, into: targets, at: path)
                                     })
        guard let found = GitRepository.containing(repository.path) else { throw WorkspaceError(message: "FAIL: missing repository") }
        let first = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        let second = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        let afterRepeat = await checks.value
        try require(first == .unmerged && second == .unmerged && afterRepeat == 1, "The merge state of a branch is computed once while nothing changes")
        _ = try await GitService.run(["branch", "-f", "main", "topic"], at: repository.path)
        let landed = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        let afterLanding = await checks.value
        try require(landed == .merged && afterLanding == 2, "Moving the main branch invalidates the cached merge state")
        _ = try await GitService.run(["branch", "-m", "main", "trunk"], at: repository.path)
        let unknown = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        try require(unknown == .unknown, "Without a main branch, the merge state is unknown")
        _ = try await GitService.run(["update-ref", "refs/remotes/origin/trunk", "trunk"], at: repository.path)
        let withoutRemoteHead = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        _ = try await GitService.run(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"], at: repository.path)
        let withRemoteHead = await cache.state(of: "topic", headSHA: head, in: found, at: found.root.path, remoteNames: [])
        try require(withoutRemoteHead == .unknown && withRemoteHead == .merged,
                    "A remote and then its HEAD added after the merge state was cached are both noticed")
        print("PASS the merge state of a branch is cached until its references change")
    }

    private actor ResolutionCount {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private static func branchComparison(root: URL) async throws {
        let require = CoreTests.require
        let parsed = GitChange.parseNameStatus(Data("M\0edited file\0R087\0old name\0new name\0D\0gone\0".utf8))
        try require(parsed.map(\.path) == ["edited file", "new name", "gone"] && parsed[1].originalPath == "old name"
                    && parsed.map { GitChangeScope.branch(ComparisonBranch(reference: "refs/heads/main")).kind(of: $0) } == [.modified, .renamed, .deleted], "Name-status parsing keeps renames and statuses")

        let repository = root.appendingPathComponent("comparison repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let commit = ["-c", "user.name=Heka Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "-m"]
        _ = try await GitService.run(["init", "-b", "main"], at: repository.path)
        try "shared\n".write(to: repository.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "doomed\n".write(to: repository.appendingPathComponent("doomed.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "-A"], at: repository.path)
        _ = try await GitService.run(commit + ["Base"], at: repository.path)
        _ = try await GitService.run(["update-ref", "refs/heads/-dangerous", "HEAD"], at: repository.path)
        _ = try await GitService.run(["switch", "-q", "-c", "feature"], at: repository.path)
        try "shared\nfeature\n".write(to: repository.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repository.appendingPathComponent("doomed.txt"))
        _ = try await GitService.run(["add", "-A"], at: repository.path)
        _ = try await GitService.run(commit + ["Feature"], at: repository.path)
        try "uncommitted\n".write(to: repository.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8)

        let main = ComparisonBranch(reference: "refs/heads/main")
        let dangerous = ComparisonBranch(reference: "refs/heads/-dangerous")
        let branches = try await InspectorService.branches(at: repository.path)
        try require(Set(branches.branches) == [main, dangerous] && branches.defaultBranch == main && branches.omitted == 0
                    && branches.preferred(over: ComparisonBranch(reference: "refs/heads/gone")) == main && main.name == "main",
                    "Comparison branches keep full references, exclude the current branch and default to main")
        let limited = try await InspectorService.branches(at: repository.path, limit: 1)
        try require(limited.branches.contains(main) && limited.branches.count <= 2 && limited.branches.count + limited.omitted == 2,
                    "A long branch list is truncated but keeps the default branch")
        let comparison = try await InspectorService.comparison(with: main, at: repository.path)
        try require(comparison.commits == 1 && comparison.changes.map(\.path) == ["doomed.txt", "shared.txt"]
                    && comparison.changes.map(\.status) == ["D", "M"], "Comparison lists committed changes since the merge base, without local edits")
        let fromDangerous = try await InspectorService.comparison(with: dangerous, at: repository.path)
        try require(fromDangerous.changes == comparison.changes, "Branch names starting with a dash are passed to Git as full references")
        let scoped = try await InspectorService.comparedChanges(with: main, at: repository.path, paths: ["shared.txt"])
        try require(scoped.map(\.path) == ["shared.txt"], "Remote diff validation only compares the requested path")
        guard let shared = comparison.changes.first(where: { $0.path == "shared.txt" }) else { fatalError("Missing compared change") }
        let diff = try await InspectorService.comparisonDiff(shared, base: main, at: repository.path)
        try require(diff.sections.map(\.kind) == [.committed] && diff.onlySection?.additions == 1 && diff.onlySection?.deletions == 0,
                    "Comparison diff shows the branch changes for one file")
        for reference in ["--output=/tmp/heka", "refs/heads/main..HEAD", "refs/heads/", "refs/tags/v1"] {
            do {
                _ = try await InspectorService.comparison(with: ComparisonBranch(reference: reference), at: repository.path)
                throw WorkspaceError(message: "FAIL: comparison base \(reference) accepted")
            } catch is ReadCommandError {}
        }
        print("PASS branch comparison lists and diffs changes against another branch")
    }

    private static func testChangeRequestPages() throws {
        let require = CoreTests.require
        let addresses = ["git@github.com:owner/app.git", "https://gitlab.example.com/group/sub/project.git", "ssh://git@gitlab.internal:2222/group/project.git",
                         "https://user:token@github.com/owner/app/", "http://gitlab.local:8080/group/project", "/Users/me/repo", "file:///tmp/repo.git",
                         "git@github.com:app.git", "./relative:path"].map(RemoteWebAddress.init(remoteURL:))
        try require(addresses.map { $0.map { "\($0.scheme)://\($0.host)\($0.port.map { ":\($0)" } ?? "")/\($0.path)" } }
                    == ["https://github.com/owner/app", "https://gitlab.example.com/group/sub/project", "https://gitlab.internal/group/project",
                        "https://github.com/owner/app", "http://gitlab.local:8080/group/project", nil, nil, nil, nil],
                    "Parse SSH, scp-like and HTTPS remotes into web addresses and reject local paths")
        try require(addresses.prefix(3).map { $0?.hosting } == [.github, .gitlab, .gitlab]
                    && RemoteWebAddress(remoteURL: "git@bitbucket.org:team/app.git")?.hosting == nil,
                    "Derive the provider from the remote host and leave unknown hosts generic")
        let github = addresses[0]?.newChangeRequestURL(branch: "feature/new #1", base: "main")?.absoluteString
        try require(github == "https://github.com/owner/app/compare/main...feature/new%20%231?expand=1", "Build the GitHub compare page for a new pull request")
        let gitlab = addresses[1]?.newChangeRequestURL(branch: "feat/a+b", base: "develop")?.absoluteString
        try require(gitlab == "https://gitlab.example.com/group/sub/project/-/merge_requests/new?merge_request%5Bsource_branch%5D=feat%2Fa%2Bb&merge_request%5Btarget_branch%5D=develop",
                    "Build the GitLab new merge request page with source and target branches")
        try require("feat/a+b&c=d;e?f#g h-é._~".percentEncodedQueryValue == "feat%2Fa%2Bb%26c%3Dd%3Be%3Ff%23g%20h-%C3%A9._~",
                    "A query value keeps only unreserved characters, so separators and plus signs never change its meaning")
        try require(addresses[4]?.newChangeRequestURL(branch: "x", base: "main")?.absoluteString.hasPrefix("http://gitlab.local:8080/group/project/-/") == true
                    && RemoteWebAddress(remoteURL: "git@bitbucket.org:team/app.git")?.newChangeRequestURL(branch: "x", base: "main") == nil,
                    "Keep HTTP ports and skip unknown providers")
        let upstream = RemoteWebAddress(remoteURL: "git@github.com:team/app.git"), fork = RemoteWebAddress(remoteURL: "git@github.com:me/app.git")
        let renamedFork = RemoteWebAddress(remoteURL: "https://github.com/me/app-fork.git")
        let gitlabUpstream = RemoteWebAddress(remoteURL: "git@gitlab.com:team/app.git"), gitlabFork = RemoteWebAddress(remoteURL: "git@gitlab.com:me/app.git")
        try require(upstream?.newChangeRequestURL(branch: "x", base: "main", from: fork)?.absoluteString == "https://github.com/team/app/compare/main...me:x?expand=1"
                    && upstream?.newChangeRequestURL(branch: "x", base: "main", from: renamedFork)?.absoluteString == "https://github.com/team/app/compare/main...me:app-fork:x?expand=1"
                    && upstream?.newChangeRequestURL(branch: "x", base: "main", from: upstream)?.absoluteString == "https://github.com/team/app/compare/main...x?expand=1"
                    && gitlabUpstream?.newChangeRequestURL(branch: "x", base: "main", from: gitlabFork)?.absoluteString.hasPrefix("https://gitlab.com/me/app/-/merge_requests/new?") == true,
                    "A branch pushed to a fork opens a cross-repository compare on GitHub and the fork's merge request page on GitLab")
        let forkRemotes = GitRemoteConfiguration(entries: [(key: "remote.origin.url", value: "git@github.com:team/app.git"),
                                                           (key: "remote.fork.url", value: "git@github.com:me/app.git"),
                                                           (key: "branch.x.pushremote", value: "fork")])
        try require(forkRemotes.pushRemote(for: "x") == "fork" && forkRemotes.pushRemote(for: "y") == "origin",
                    "A branch is pushed to its push remote, else origin")
        try require(ComparisonBranch(reference: "refs/remotes/origin/release/1.0").hostedName == "release/1.0"
                    && ComparisonBranch(reference: "refs/heads/feature/x").hostedName == "feature/x",
                    "Target the branch name without its remote")
        func forkSnapshot(_ remotes: [(String, String)], push: String, hosting host: String = "github.com") -> LocalGitSnapshot {
            let configuration = GitRemoteConfiguration(entries: remotes.map { (key: "remote.\($0.0).url", value: "git@\(host):\($0.1).git") })
            return LocalGitSnapshot(root: "/r", branch: GitBranch(name: "x"), headSHA: "abc", changes: [],
                                    tracking: GitTracking(upstream: "\(push)/x", tracksSameBranch: true),
                                    remoteWebAddresses: configuration.webAddresses, primaryRemote: configuration.primaryName, pushRemote: push)
        }
        let originFork = forkSnapshot([("origin", "me/app"), ("upstream", "team/app")], push: "origin")
        let originTeam = forkSnapshot([("origin", "team/app"), ("fork", "me/app")], push: "fork")
        let gitlabOriginFork = forkSnapshot([("origin", "me/app"), ("upstream", "team/app")], push: "origin", hosting: "gitlab.com")
        let slashRemote = forkSnapshot([("origin", "me/app"), ("team/main", "team/app")], push: "origin")
        try require(originFork.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/upstream/main"))?.absoluteString
                        == "https://github.com/team/app/compare/main...me:x?expand=1"
                    && originFork.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/upstream/release/1.0"))?.absoluteString
                        == "https://github.com/team/app/compare/release/1.0...me:x?expand=1"
                    && originFork.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/origin/main"))?.absoluteString
                        == "https://github.com/me/app/compare/main...x?expand=1"
                    && originFork.newChangeRequestURL(into: ComparisonBranch(reference: "refs/heads/main"))?.absoluteString
                        == "https://github.com/me/app/compare/main...x?expand=1"
                    && originTeam.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/origin/main"))?.absoluteString
                        == "https://github.com/team/app/compare/main...me:x?expand=1"
                    && slashRemote.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/team/main/dev"))?.absoluteString
                        == "https://github.com/team/app/compare/dev...me:x?expand=1",
                    "A pull request targets the repository of the base's remote and names the fork's owner when the branch is pushed elsewhere")
        try require(gitlabOriginFork.newChangeRequestURL(into: ComparisonBranch(reference: "refs/remotes/upstream/main"))?.absoluteString
                        == "https://gitlab.com/me/app/-/merge_requests/new?merge_request%5Bsource_branch%5D=x&merge_request%5Btarget_branch%5D=main",
                    "A merge request opens on the source project with the base branch without its remote")
        print("PASS change request pages for GitHub and GitLab remotes")
    }
}

private extension URL {
    func withExtension(_ ext: String) -> URL { appendingPathExtension(ext) }
}
