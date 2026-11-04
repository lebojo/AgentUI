import Foundation

enum InspectorTests {
    static func run(root: URL, repository: URL, unborn: URL) async throws {
        let require = CoreTests.require
        let renamed = GitChange.parsePorcelain(Data("R  renamed file\0original\nfile\0 M café.swift\0?? untracked\0".utf8))
        try require(renamed.count == 3 && renamed[0].originalPath == "original\nfile" && renamed[1].path == "café.swift" && renamed[2].isUntracked, "NUL status parsing preserves renames, spaces, Unicode and newlines")
        let file = repository.appendingPathComponent("tracked file.txt")
        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "--", "tracked file.txt"], at: repository.path)
        _ = try await GitService.run(["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-m", "Tracked fixture"], at: repository.path)
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
        try require(headOnly.changes.isEmpty && headOnly.headSHA == local.headSHA && single.changes.map(\.path) == ["tracked file.txt"],
                    "Remote checks skip git status and remote diffs only check the requested path")
        let empty = try await InspectorService.localGit(at: unborn.path)
        try require(empty.headSHA == nil && empty.branch?.name == "develop", "Inspector supports unborn HEAD")
        print("PASS inspector status and real staged/unstaged diffs")

        try await branchComparison(root: root)

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
                     "git@github.com:owner/app.git", "https://github.com/owner/app.git"].map(GitHosting.init(remoteURL:))
        try require(hosts == [.gitlab, .gitlab, .gitlab, .github, .github], "Detect GitLab and GitHub from remote URLs")
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

    private static func branchComparison(root: URL) async throws {
        let require = CoreTests.require
        let parsed = GitChange.parseNameStatus(Data("M\0edited file\0R087\0old name\0new name\0D\0gone\0".utf8))
        try require(parsed.map(\.path) == ["edited file", "new name", "gone"] && parsed[1].originalPath == "old name"
                    && parsed.map(\.description) == ["Modified", "Renamed", "Deleted"], "Name-status parsing keeps renames and statuses")

        let repository = root.appendingPathComponent("comparison repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let commit = ["-c", "user.name=AgentUI Tests", "-c", "user.email=tests@example.invalid", "commit", "-q", "-m"]
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
        for reference in ["--output=/tmp/agentui", "refs/heads/main..HEAD", "refs/heads/", "refs/tags/v1"] {
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
        try require(gitlab == "https://gitlab.example.com/group/sub/project/-/merge_requests/new?merge_request%5Bsource_branch%5D=feat/a%2Bb&merge_request%5Btarget_branch%5D=develop",
                    "Build the GitLab new merge request page with source and target branches")
        try require(addresses[4]?.newChangeRequestURL(branch: "x", base: "main")?.absoluteString.hasPrefix("http://gitlab.local:8080/group/project/-/") == true
                    && RemoteWebAddress(remoteURL: "git@bitbucket.org:team/app.git")?.newChangeRequestURL(branch: "x", base: "main") == nil,
                    "Keep HTTP ports and skip unknown providers")
        try require(ComparisonBranch(reference: "refs/remotes/origin/release/1.0").hostedName == "release/1.0"
                    && ComparisonBranch(reference: "refs/heads/feature/x").hostedName == "feature/x",
                    "Target the branch name without its remote")
        print("PASS change request pages for GitHub and GitLab remotes")
    }
}

private extension URL {
    func withExtension(_ ext: String) -> URL { appendingPathExtension(ext) }
}
