import Foundation

protocol Installer: Sendable {
    var status: InstallationStatus { get }
    func install() throws
    func uninstall() throws
}

enum InstallationStatus: Equatable, Sendable {
    case notInstalled, incomplete, outdated, installed, conflict

    var title: String {
        switch self {
        case .notInstalled: "Non installé"
        case .incomplete: "Installation incomplète"
        case .outdated: "Mise à jour disponible"
        case .installed: "Installé"
        case .conflict: "Un autre fichier porte ce nom"
        }
    }

    var actionTitle: String {
        switch self {
        case .incomplete: "Réparer"
        case .outdated: "Mettre à jour"
        case .notInstalled, .installed, .conflict: "Installer"
        }
    }

    var canInstall: Bool { self != .installed && self != .conflict }
    var canUninstall: Bool { self != .notInstalled && self != .conflict }
}
