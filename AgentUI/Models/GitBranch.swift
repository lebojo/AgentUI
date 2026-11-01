import Foundation

struct GitBranch: Codable, Equatable, Sendable {
    let name: String
    var isDetached = false

    var accessibilityLabel: String {
        isDetached ? String(localized: "Detached HEAD, commit \(name)") : String(localized: "Git branch: \(name)")
    }
}

