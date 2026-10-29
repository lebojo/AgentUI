import Foundation
import Darwin

struct GitBranch: Equatable, Sendable {
    let name: String
    var isDetached = false

    var accessibilityLabel: String {
        isDetached ? "HEAD détachée, commit \(name)" : "Branche Git : \(name)"
    }
}

struct GitRepository: Sendable {
    let root: URL
    let branch: GitBranch
    let gitDirectory: URL
    let commonDirectory: URL

    static func atRoot(_ location: URL) -> GitRepository? {
        let url = URL(fileURLWithPath: WorkspaceDisk.canonicalPath(location))
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
            gitDirectory = resolve(location, relativeTo: url)
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
        return GitRepository(root: url, branch: branch, gitDirectory: gitDirectory, commonDirectory: common)
    }

    static func containing(_ path: String) -> GitRepository? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        var directory = URL(fileURLWithPath: WorkspaceDisk.canonicalPath(URL(fileURLWithPath: path)))
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
        let remaining = skippedDirectories.count > 5 ? "\n… et \(skippedDirectories.count - 5) autres." : ""
        return "Certains dossiers n’ont pas pu être lus :\n\(paths)\(remaining)"
    }
}

enum RepositoryDiscovery {
    static func repositories(in folder: URL) async throws -> [URL] {
        try await scan(in: folder).repositories
    }

    @concurrent static func scan(in folder: URL) async throws -> RepositoryDiscoveryResult {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let excluded: Set<String> = ["node_modules", "Pods", "Carthage", "DerivedData", "venv"]
        let root = URL(fileURLWithPath: WorkspaceDisk.canonicalPath(folder))
        var pending = [root]
        var visited: Set<String> = []
        var found: [URL] = []
        var skipped: Set<String> = []
        while let directory = pending.popLast() {
            try Task.checkCancellation()
            let canonical = WorkspaceDisk.canonicalPath(directory)
            guard !visited.contains(canonical) else { continue }
            if GitRepository.atRoot(directory) != nil {
                visited.insert(canonical)
                found.append(URL(fileURLWithPath: canonical))
                continue
            }
            do {
                let values = try directory.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { continue }
                visited.insert(canonical)
                let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                for child in children {
                    do {
                        let values = try child.resourceValues(forKeys: keys)
                        guard !excluded.contains(child.lastPathComponent), values.isPackage != true,
                              values.isDirectory == true || values.isSymbolicLink == true else { continue }
                        pending.append(child)
                    } catch { skipped.insert(child.path) }
                }
            } catch {
                if directory == root { throw error }
                skipped.insert(directory.path)
            }
        }
        return RepositoryDiscoveryResult(
            repositories: found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            skippedDirectories: skipped.sorted())
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
