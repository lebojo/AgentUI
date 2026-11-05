import SwiftUI

struct MobileTerminalViewport: UIViewRepresentable {
    @AppStorage(TerminalAppearance.mobileFontSizeKey) private var fontSize = TerminalAppearance.defaultFontSize

    let session: MobileTerminalSession

    func makeUIView(context: Context) -> MobileTerminalScrollView {
        MobileTerminalScrollView(session: session)
    }

    func updateUIView(_ uiView: MobileTerminalScrollView, context: Context) {
        session.setFontSize(fontSize)
        uiView.setCanvasSize(session.canvasSize)
    }
}
