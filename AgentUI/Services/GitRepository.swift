import Foundation
import Darwin

struct GitRepository: Sendable {
    let root: URL
    let branch: GitBranch
    let gitDirectory: URL
    let commonDirectory: URL

    static func atRoot(_ location: URL) -> GitRepository? {
        let url = URL(fileURLWithPath: WorkspacePath.canonical(location))
        let fm = FileManager.default
        let marker = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: marker.path, isDirectory: &isDirectory) else { return nil }
        let gitDirectory: URL
        if isDirectory.boolValue {
            gitDirectory = marker
        } else {
            guard let gitfile = smallTextFile(marker), gitfile.hasPrefix("gitdir: ") else { return nil }
            let location = String(gitfile.dropFirst("gitdir: ".count))
            gitDirectory = URL(fileURLWithPath: WorkspacePath.canonical(resolve(location, relativeTo: url)))
        }
        let common = smallTextFile(gitDirectory.appendingPathComponent("commondir"))
            .map { resolve($0, relativeTo: gitDirectory) } ?? gitDirectory
        var objectsAreDirectory: ObjCBool = false
        guard fm.fileExists(atPath: common.appendingPathComponent("objects").path, isDirectory: &objectsAreDirectory),
              objectsAreDirectory.boolValue,
              let head = smallTextFile(gitDirectory.appendingPathComponent("HEAD")) else { return nil }
        let branch: GitBranch
        if head.hasPrefix("ref: refs/heads/") {
            let name = String(head.dropFirst("ref: refs/heads/".count))
            guard !name.isEmpty else { return nil }
            branch = GitBranch(name: name)
        } else if [40, 64].contains(head.count), head.allSatisfy(\.isHexDigit) {
            branch = GitBranch(name: String(head.prefix(7)), isDetached: true)
        } else {
            return nil
        }
        return GitRepository(root: url, branch: branch, gitDirectory: gitDirectory,
                             commonDirectory: URL(fileURLWithPath: WorkspacePath.canonical(common)))
    }

    func divergentBranch(from worktree: GitRepository?) -> GitBranch? {
        guard let worktree, commonDirectory.path == worktree.commonDirectory.path, branch != worktree.branch else { return nil }
        return branch
    }

    static func containing(_ path: String) -> GitRepository? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        var directory = URL(fileURLWithPath: WorkspacePath.canonical(URL(fileURLWithPath: path)))
        while true {
            if fm.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                return atRoot(directory)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    @concurrent static func repositories(containing paths: [String]) async -> [GitRepository] {
        paths.compactMap(containing)
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        (path as NSString).isAbsolutePath ? URL(fileURLWithPath: path) : base.appendingPathComponent(path).standardizedFileURL
    }

    private static func smallTextFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), data.count < 8192,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RepositoryDiscoveryResult: Sendable {
    var repositories: [URL]
    var skippedDirectories: [String]

    var warning: String? {
        guard !skippedDirectories.isEmpty else { return nil }
        let paths = skippedDirectories.prefix(5).joined(separator: "\n")
        let remaining = skippedDirectories.count > 5 ? "\n" + String(localized: "… and \(skippedDirectories.count - 5) more.") : ""
        return String(localized: "Some folders couldn’t be read:") + "\n\(paths)\(remaining)"
    }
}

enum RepositoryDiscovery {
    static func repositories(in folder: URL) async throws -> [URL] {
        try await scan(in: folder).repositories
    }

    @concurrent static func scan(in folder: URL) async throws -> RepositoryDiscoveryResult {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let root = URL(fileURLWithPath: WorkspacePath.canonical(folder))
        var pending: [(directory: URL, enclosing: String?)] = [(root, nil)]
        var visited: Set<String> = []
        var found: Set<String> = []
        var skipped: Set<String> = []
        while let (directory, enclosing) = pending.popLast() {
            try Task.checkCancellation()
            let canonical = WorkspacePath.canonical(directory)
            guard !visited.contains(canonical) else { continue }
            var gitStorage = enclosing
            if let repository = GitRepository.atRoot(directory) {
                let storage = WorkspacePath.canonical(repository.commonDirectory)
                if let enclosing, belongs(storage, to: enclosing) {
                    visited.insert(canonical)
                    continue
                }
                found.insert(canonical)
                gitStorage = storage
            }
            do {
                let values = try directory.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { continue }
                visited.insert(canonical)
                let excluded = gitStorage == nil ? excludedDirectories : excludedDirectories.union(buildDirectories)
                let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                for child in children {
                    do {
                        let values = try child.resourceValues(forKeys: keys)
                        guard !excluded.contains(child.lastPathComponent), values.isPackage != true,
                              values.isDirectory == true || values.isSymbolicLink == true else { continue }
                        pending.append((child, gitStorage))
                    } catch { skipped.insert(child.path) }
                }
            } catch {
                if directory == root { throw error }
                skipped.insert(directory.path)
            }
        }
        return RepositoryDiscoveryResult(
            repositories: found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { URL(fileURLWithPath: $0) },
            skippedDirectories: skipped.sorted())
    }

    private static let excludedDirectories: Set<String> = ["node_modules", "Pods", "Carthage", "DerivedData", "venv"]
    private static let buildDirectories: Set<String> = ["target", "build", "dist", "vendor"]

    private static func belongs(_ storage: String, to enclosing: String) -> Bool {
        storage == enclosing || storage.hasPrefix(enclosing + "/")
    }
}

enum TerminalProcessDirectory {
    static func read(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let path = String(cString: $0)
                return path.isEmpty ? nil : path
            }
        }
    }
}

enum WorktreeFolder {
    @concurrent static func scan(_ roots: [URL]) async -> [DiscoveredWorktree] {
        roots.flatMap { root in
            ((try? WorkspaceDisk.childDirectories(of: root)) ?? []).compactMap(worktree)
        }
    }

    private static func worktree(at url: URL) -> DiscoveredWorktree? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        let path = WorkspacePath.canonical(url)
        guard let repository = GitRepository.atRoot(url) else {
            return DiscoveredWorktree(path: path, branch: nil, repositoryPath: nil)
        }
        return DiscoveredWorktree(path: path, branch: repository.branch.name,
                                  repositoryPath: mainWorktree(of: repository.commonDirectory).map(WorkspacePath.canonical))
    }

    static func registration(of worktree: URL) -> URL? {
        guard let repository = GitRepository.atRoot(worktree),
              repository.gitDirectory.deletingLastPathComponent().path
                == repository.commonDirectory.appendingPathComponent("worktrees").path else { return nil }
        return repository.gitDirectory
    }

    private static func mainWorktree(of commonDirectory: URL) -> URL? {
        if commonDirectory.lastPathComponent == ".git" { return commonDirectory.deletingLastPathComponent() }
        guard let configured = coreSetting("worktree", in: commonDirectory) else { return nil }
        return (configured as NSString).isAbsolutePath
            ? URL(fileURLWithPath: configured)
            : commonDirectory.appendingPathComponent(configured).standardizedFileURL
    }

    static func coreSetting(_ name: String, in commonDirectory: URL) -> String? {
        guard let text = try? String(contentsOf: commonDirectory.appendingPathComponent("config"), encoding: .utf8) else { return nil }
        var inCore = false
        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") { inCore = line.lowercased() == "[core]" }
            guard inCore else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == name { return parts[1] }
        }
        return nil
    }
}
