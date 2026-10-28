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
        try require(untrackedPreview == "new text", "Preview new files inside untracked directories")
        guard let change = local.changes.first(where: { $0.path == "tracked file.txt" }) else { fatalError("Missing tracked change") }
        try require(change.status == "MM" && local.branch?.name == "main" && local.headSHA?.count == 40, "Real Git snapshot includes staged and unstaged state")
        let diff = try await InspectorService.diff(change, at: repository.path)
        try require(diff.contains("+staged") && diff.contains("+unstaged"), "Preview both index and worktree diffs")
        let empty = try await InspectorService.localGit(at: unborn.path)
        try require(empty.headSHA == nil && empty.branch?.name == "develop", "Inspector supports unborn HEAD")
        print("PASS inspector status and real staged/unstaged diffs")

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
        try require(preview.contains("128 Ko") && preview.count < 132_000, "Bound large text previews")
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
        try require(remote.pullRequest?.number == 42 && remote.pullRequest?.statusCheckRollup?.count == 2 && remote.runs.first?.headSha == "local-sha", "Decode PR checks, legacy status contexts and commit-filtered runs")
        let noPR = try await InspectorService.github(at: repository.path, branch: GitBranch(name: "none", isDetached: false), headSHA: nil, executable: fake)
        try require(noPR.pullRequest == nil && noPR.pullRequestError == nil, "No PR is a valid empty state")
        let offline = try await InspectorService.github(at: repository.path, branch: GitBranch(name: "offline", isDetached: false), headSHA: nil, executable: fake)
        try require(offline.pullRequestError?.contains("connecting") == true, "Network failure is not reported as no PR")
        let calls = try String(contentsOf: fake.withExtension("calls"), encoding: .utf8)
        try require(calls.contains("--commit") && calls.contains("local-sha"), "gh Actions query filters current commit")
        print("PASS gh JSON decoding, commit filtering, no PR and network failures")

        do {
            _ = try await ReadCommand.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], at: root.path, timeout: 0.1)
            throw WorkspaceError(message: "FAIL: timeout missing")
        } catch let error as ReadCommandError { try require(error.message.contains("temps"), "Timed out query reports error") }
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
        } catch let error as ReadCommandError { try require(error.message.contains("limite"), "Stop excessive output while query runs") }
        try require(Date().timeIntervalSince(start) < 2, "Output termination should precede timeout")
        print("PASS query cancellation, timeout and live output limit")
    }
}

private extension URL {
    func withExtension(_ ext: String) -> URL { appendingPathExtension(ext) }
}
