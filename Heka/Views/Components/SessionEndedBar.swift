import SwiftUI

struct SessionEndedBar<Accessory: View>: View {
    let session: TerminalSession
    let reopen: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        if session.hasExited {
            HStack {
                SessionExitLabel(code: session.exitCode)
                Spacer()
                accessory
                Button("Reopen Terminal", action: reopen)
            }
            .font(Typography.body).padding(Spacing.l).background(Palette.bar)
        }
    }
}

extension SessionEndedBar where Accessory == EmptyView {
    init(session: TerminalSession, reopen: @escaping () -> Void) {
        self.init(session: session, reopen: reopen) { EmptyView() }
    }
}
