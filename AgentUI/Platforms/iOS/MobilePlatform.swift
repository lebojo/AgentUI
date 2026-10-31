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

    func submitsOnReturn(_ text: Binding<String>, perform submit: @escaping () -> Void) -> some View {
        onChange(of: text.wrappedValue) { old, new in
            guard new.count == old.count + 1, new.filter(\.isNewline).count > old.filter(\.isNewline).count else { return }
            text.wrappedValue = old
            submit()
        }
    }

    func previewSheetFrame(idealWidth: CGFloat, idealHeight: CGFloat) -> some View {
        frame(idealWidth: idealWidth, idealHeight: idealHeight)
    }
}
