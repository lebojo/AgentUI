import Foundation

enum AgentSkillStatus: Equatable, Sendable {
    case notInstalled, outdated, installed

    var title: String {
        switch self {
        case .notInstalled: "Non installé"
        case .outdated: "Mise à jour disponible"
        case .installed: "Installé"
        }
    }

    var actionTitle: String {
        switch self {
        case .outdated: "Mettre à jour"
        case .notInstalled, .installed: "Installer"
        }
    }

    var isPresent: Bool { self != .notInstalled }
    var needsInstall: Bool { self != .installed }
}
