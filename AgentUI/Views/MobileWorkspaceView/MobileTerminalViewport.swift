import SwiftUI
import SwiftTerm

struct MobileTerminalViewport: UIViewRepresentable {
    let terminal: TerminalView
    let canvasSize: CGSize
    let fit: (CGSize) -> Void

    func makeUIView(context: Context) -> MobileTerminalScrollView {
        MobileTerminalScrollView(terminal: terminal, fit: fit)
    }

    func updateUIView(_ uiView: MobileTerminalScrollView, context: Context) {
        uiView.setCanvasSize(canvasSize)
    }
}
