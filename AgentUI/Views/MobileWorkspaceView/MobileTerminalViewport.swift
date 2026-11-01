import SwiftUI
import SwiftTerm

struct MobileTerminalViewport: UIViewRepresentable {
    let terminal: TerminalView
    let canvasSize: CGSize

    func makeUIView(context: Context) -> MobileTerminalScrollView {
        MobileTerminalScrollView(terminal: terminal)
    }

    func updateUIView(_ uiView: MobileTerminalScrollView, context: Context) {
        uiView.setCanvasSize(canvasSize)
    }
}
