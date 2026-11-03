import SwiftUI

struct MobileTerminalViewport: View {
    @AppStorage(TerminalAppearance.mobileFontSizeKey) private var fontSize = TerminalAppearance.defaultFontSize

    let session: MobileTerminalSession

    var body: some View {
        MobileTerminalCanvas(session: session)
            .onChange(of: fontSize, initial: true) { session.setFontSize(fontSize) }
    }
}
