import SwiftUI

@MainActor enum PlatformClipboard {
    static func copy(_ text: String) { UIPasteboard.general.string = text }
}

extension Color {
    static let systemTertiaryLabel = Color(uiColor: .tertiaryLabel)
    static let systemSurface = Color(uiColor: .systemBackground)
    static let systemControl = Color(uiColor: .secondarySystemBackground)
    static let systemFill = Color(uiColor: .quaternaryLabel)
}

extension View {
    func commandInputTraits() -> some View { textInputAutocapitalization(.never) }

    func previewSheetFrame(idealWidth: CGFloat, idealHeight: CGFloat) -> some View {
        frame(idealWidth: idealWidth, idealHeight: idealHeight)
    }
}
