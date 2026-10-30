import Foundation

struct GitBranch: Codable, Equatable, Sendable {
    let name: String
    var isDetached = false

    var accessibilityLabel: String {
        isDetached ? "HEAD détachée, commit \(name)" : "Branche Git : \(name)"
    }
}

