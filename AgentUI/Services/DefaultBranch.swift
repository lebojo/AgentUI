import Foundation

enum DefaultBranch {
    static let conventionalNames = ["main", "master"]
    private static let originPrefix = "refs/remotes/origin/"

    struct RemoteHead: Equatable, Sendable {
        let name: String
        let reference: String

        var isOrigin: Bool { reference.hasPrefix(DefaultBranch.originPrefix) }
    }

    static func names(remoteHeads: some Sequence<String>) -> Set<String> {
        Set(conventionalNames).union(remoteHeads)
    }

    static func references(remoteHeads: [RemoteHead]) -> [String] {
        let heads = remoteHeads.filter(\.isOrigin) + remoteHeads.filter { !$0.isOrigin }
        let local = (heads.map(\.name) + conventionalNames).map { "refs/heads/" + $0 }
        let remote = conventionalNames.map { originPrefix + $0 }
        return unique(heads.map(\.reference) + local + remote)
    }

    static func preferredReferences(remoteHead: String?) -> [String] {
        references(remoteHeads: remoteHeads(in: remoteHead.map { originPrefix + "HEAD\t" + $0 } ?? ""))
    }

    static func remoteHeads(in output: String) -> [RemoteHead] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2, fields[0].hasSuffix("/HEAD") else { return nil }
            let remote = String(fields[0].dropLast("HEAD".count))
            guard fields[1].hasPrefix(remote), fields[1].count > remote.count else { return nil }
            return RemoteHead(name: String(fields[1].dropFirst(remote.count)), reference: fields[1])
        }
    }

    static func mergeTargets(in output: String, candidates: [String]) -> [String] {
        let wanted = Set(candidates)
        var targets: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) + ["", ""]
            guard wanted.contains(fields[0]) else { continue }
            targets.append(fields[0])
            if fields[1].hasPrefix("refs/"), fields[2] != "[gone]" { targets.append(fields[1]) }
        }
        return unique(targets)
    }

    private static func unique(_ references: [String]) -> [String] {
        references.reduce(into: []) { unique, reference in
            if !unique.contains(reference) { unique.append(reference) }
        }
    }
}
