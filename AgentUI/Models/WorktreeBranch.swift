import Foundation

enum WorktreeBranch: Equatable, Sendable {
    case deletable(String)
    case protected(String, Protection)
    case none
    case unreadable

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
        case .unreadable:
            String(localized: "The worktree’s branch couldn’t be checked, so it won’t be deleted. Nothing was removed.")
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

struct UnmergedBranchError: LocalizedError, Equatable, Sendable {
    let branch: String
    let hasMainBranch: Bool

    var reason: String {
        hasMainBranch ? String(localized: "The branch “\(branch)” isn’t merged into the main branch.")
            : String(localized: "The repository’s main branch couldn’t be found, so the branch “\(branch)” can’t be checked.")
    }

    var errorDescription: String? { String(localized: "\(reason) Nothing was removed.") }
}

enum BranchCleanup: Equatable, Sendable {
    case notRequested, untouched, unchecked, deleted(String), kept(String, reason: String)

    var branch: String? {
        switch self {
        case .notRequested, .untouched, .unchecked: nil
        case .deleted(let name), .kept(let name, _): name
        }
    }

    var isDeleted: Bool {
        if case .deleted = self { true } else { false }
    }

    var reportedDeletion: Bool? { self == .notRequested ? nil : isDeleted }

    var notice: String? {
        guard case .untouched = self else { return nil }
        return String(localized: "The worktree was deleted. It wasn’t on a branch, so no branch was deleted.")
    }

    var failure: String? {
        switch self {
        case .notRequested, .untouched, .deleted: nil
        case .unchecked: String(localized: "The worktree was deleted, but its branch couldn’t be checked, so it was kept.")
        case .kept(_, let reason): String(localized: "The worktree was deleted, but not its branch. \(reason)")
        }
    }
}
