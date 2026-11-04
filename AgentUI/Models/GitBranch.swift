import Foundation

struct GitBranch: Codable, Equatable, Sendable {
    let name: String
    var isDetached = false

    var symbolName: String { isDetached ? "point.topleft.down.to.point.bottomright.curvepath" : "arrow.triangle.branch" }

    var accessibilityLabel: String {
        isDetached ? String(localized: "Detached HEAD, commit \(name)") : String(localized: "Git branch: \(name)")
    }
}


struct BranchSuggestion: Identifiable, Hashable, Sendable {
    enum Origin: Hashable, Sendable {
        case local
        case remote(String)
    }

    let name: String
    let origin: Origin

    var id: String { name }
    var remote: String? {
        if case .remote(let name) = origin { name } else { nil }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || (name != query && name.localizedCaseInsensitiveContains(query))
    }
}
