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

    static func names(remoteHeads: some Sequence<String>) -> Set<String> {
        Set(conventionalNames).union(remoteHeads)
    }

    static func preferredReferences(remoteHead: String?) -> [String] {
        [remoteHead].compactMap { $0 } + conventionalNames.map { "refs/heads/" + $0 } + conventionalNames.map { "refs/remotes/origin/" + $0 }
    }
}

enum BranchRemoval: Sendable {
    case keep, merged, force

    func arguments(for branch: String) -> [String]? {
        switch self {
        case .keep: nil
        case .merged: ["branch", "-d", "--", branch]
        case .force: ["branch", "-D", "--", branch]
        }
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
