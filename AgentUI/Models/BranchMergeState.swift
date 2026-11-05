import Foundation

enum BranchMergeState: String, Codable, Sendable {
    case merged, unmerged, unknown
}
