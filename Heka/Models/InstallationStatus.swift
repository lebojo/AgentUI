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
        case .notInstalled: String(localized: "Not Installed")
        case .incomplete: String(localized: "Incomplete Installation")
        case .outdated: String(localized: "Update Available")
        case .installed: String(localized: "Installed")
        case .conflict: String(localized: "Another file has this name")
        }
    }

    var actionTitle: String {
        switch self {
        case .incomplete: String(localized: "Repair")
        case .outdated: String(localized: "Update")
        case .notInstalled, .installed, .conflict: String(localized: "Install")
        }
    }

    var canInstall: Bool { self != .installed && self != .conflict }
    var canUninstall: Bool { self != .notInstalled && self != .conflict }
}
