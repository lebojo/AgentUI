import SwiftUI
import SwiftTerm

struct MobileTerminalViewport: UIViewRepresentable {
    let session: MobileTerminalSession
    let terminal: TerminalView
    let canvasSize: CGSize

    func makeUIView(context: Context) -> MobileTerminalScrollView {
        MobileTerminalScrollView(session: session, terminal: terminal)
    }

    func updateUIView(_ uiView: MobileTerminalScrollView, context: Context) {
        uiView.setCanvasSize(canvasSize)
    }
}
