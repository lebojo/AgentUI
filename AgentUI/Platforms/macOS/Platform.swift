import SwiftUI
import AppKit

@MainActor enum PlatformClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension Color {
    static let systemTertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let systemSurface = Color(nsColor: .textBackgroundColor)
    static let systemControl = Color(nsColor: .controlBackgroundColor)
    static let systemFill = Color(nsColor: .quaternaryLabelColor)
}

extension View {
    func commandInputTraits() -> some View { self }

    func submitsOnReturn(_ text: Binding<String>, perform submit: @escaping () -> Void) -> some View {
        onSubmit(submit)
    }

    func previewSheetFrame(idealWidth: CGFloat, idealHeight: CGFloat) -> some View {
        frame(minWidth: Dimension.PreviewSheet.minWidth, idealWidth: idealWidth, maxWidth: .infinity,
              minHeight: Dimension.PreviewSheet.minHeight, idealHeight: idealHeight, maxHeight: .infinity)
    }
}
