import Foundation

struct AgentPrompts: Codable, Hashable, Sendable {
    static let defaultCommit = """
    Please create commits for the uncommitted changes in this repository (staged, unstaged and untracked files). \
    Group related changes into small, coherent commits and write each message in the same style as the existing \
    history (read `git log` first). Do not push.
    """
    static let defaultChangeRequest = """
    Please open a pull request (or merge request on GitLab) for the current branch against its base branch. \
    Read the commits and the diff, then write a clear title and a description that follows the conventions of \
    this repository. Push the branch first if it has no upstream. Use `gh` for GitHub or `glab` for GitLab.
    """

    var commit = Self.defaultCommit
    var changeRequest = Self.defaultChangeRequest

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commit = try container.decodeIfPresent(String.self, forKey: .commit) ?? Self.defaultCommit
        changeRequest = try container.decodeIfPresent(String.self, forKey: .changeRequest) ?? Self.defaultChangeRequest
    }
}
