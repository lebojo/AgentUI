import Foundation

enum SidebarItemKind: Sendable {
    case folder, project

    var defaultSymbol: SidebarSymbol {
        switch self {
        case .folder: .folder
        case .project: .shippingBox
        }
    }
}

struct SidebarAppearance: Equatable, Sendable {
    let kind: SidebarItemKind
    var symbol: SidebarSymbol?
    var tint: SidebarTint?

    var displaySymbol: SidebarSymbol { symbol ?? kind.defaultSymbol }
}

enum SidebarSymbol: String, CaseIterable, Codable, Identifiable, Sendable {
    case folder = "folder"
    case shippingBox = "shippingbox"
    case archiveBox = "archivebox"
    case trayFull = "tray.full"
    case terminal = "terminal"
    case code = "chevron.left.forwardslash.chevron.right"
    case hammer = "hammer"
    case wrench = "wrench.and.screwdriver"
    case gear = "gearshape"
    case cpu = "cpu"
    case server = "server.rack"
    case cloud = "cloud"
    case globe = "globe"
    case iphone = "iphone"
    case laptop = "laptopcomputer"
    case gameController = "gamecontroller"
    case testTube = "testtube.2"
    case ant = "ant"
    case lockShield = "lock.shield"
    case puzzle = "puzzlepiece"
    case cube = "cube"
    case chart = "chart.bar"
    case book = "book"
    case document = "doc.text"
    case briefcase = "briefcase"
    case graduationCap = "graduationcap"
    case people = "person.2"
    case bubbles = "bubble.left.and.bubble.right"
    case cart = "cart"
    case paintbrush = "paintbrush"
    case photo = "photo"
    case music = "music.note"
    case sparkles = "sparkles"
    case star = "star"
    case heart = "heart"
    case bolt = "bolt"
    case leaf = "leaf"
    case flag = "flag"

    var id: Self { self }
    var systemName: String { rawValue }
}

enum SidebarTint: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown, gray

    var id: Self { self }

    var title: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .mint: String(localized: "Mint")
        case .teal: String(localized: "Teal")
        case .cyan: String(localized: "Cyan")
        case .brown: String(localized: "Brown")
        case .gray: String(localized: "Gray")
        }
    }
}
