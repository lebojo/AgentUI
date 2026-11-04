import Foundation

enum WorktreeBranch: Equatable, Sendable {
    case deletable(String)
    case protected(String, Protection)
    case none

    enum Protection: Equatable, Sendable {
        case defaultBranch, checkedOutElsewhere
    }

    init(_ branch: GitBranch?, defaultBranches: Set<String>, checkedOutElsewhere: Set<String>) {
        guard let branch, !branch.isDetached, !branch.name.isEmpty else { self = .none; return }
        if defaultBranches.contains(branch.name) { self = .protected(branch.name, .defaultBranch) }
        else if checkedOutElsewhere.contains(branch.name) { self = .protected(branch.name, .checkedOutElsewhere) }
        else { self = .deletable(branch.name) }
    }

    var deletableName: String? {
        if case .deletable(let name) = self { name } else { nil }
    }

    var refusal: String? {
        switch self {
        case .deletable, .none: nil
        case .protected(let name, .defaultBranch):
            String(localized: "The branch “\(name)” is the repository’s main branch and won’t be deleted. Nothing was removed.")
        case .protected(let name, .checkedOutElsewhere):
            String(localized: "The branch “\(name)” is checked out in another worktree and won’t be deleted. Nothing was removed.")
        }
    }
}

enum DefaultBranch {
    static let conventionalNames = ["main", "master"]

    struct RemoteHead: Equatable, Sendable {
        let name: String
        let reference: String
    }

    static func names(remoteHeads: some Sequence<String>) -> Set<String> {
        Set(conventionalNames).union(remoteHeads)
    }

    static func preferredReferences(remoteHead: String?) -> [String] {
        [remoteHead].compactMap { $0 } + conventionalNames.map { "refs/heads/" + $0 } + conventionalNames.map { "refs/remotes/origin/" + $0 }
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

    static func candidateReferences(names: Set<String>, remoteHeads: [RemoteHead]) -> [String] {
        names.sorted().map { "refs/heads/" + $0 } + remoteHeads.map(\.reference)
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
        return targets.reduce(into: []) { unique, target in
            if !unique.contains(target) { unique.append(target) }
        }
    }
}

enum BranchRemoval: Sendable {
    case keep, merged, force

    var requiresMerge: Bool { self == .merged }

    func arguments(for branch: String) -> [String]? {
        self == .keep ? nil : ["branch", "-D", "--", branch]
    }
}

enum BranchCleanup: Equatable, Sendable {
    case untouched, deleted(String), kept(String, reason: String)

    var branch: String? {
        switch self {
        case .untouched: nil
        case .deleted(let name), .kept(let name, _): name
        }
    }

    var isDeleted: Bool {
        if case .deleted = self { true } else { false }
    }

    var notice: String? {
        guard case .untouched = self else { return nil }
        return String(localized: "The worktree was deleted. It wasn’t on a branch, so no branch was deleted.")
    }

    var failure: String? {
        guard case .kept(_, let reason) = self else { return nil }
        return String(localized: "The worktree was deleted, but not its branch. \(reason)")
    }
}
