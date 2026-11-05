import SwiftUI

struct MobileTerminalCanvas: UIViewRepresentable {
    let session: MobileTerminalSession

    func makeUIView(context: Context) -> MobileTerminalScrollView {
        MobileTerminalScrollView(session: session)
    }

    func updateUIView(_ uiView: MobileTerminalScrollView, context: Context) {
        uiView.setCanvasSize(session.canvasSize)
    }
}
