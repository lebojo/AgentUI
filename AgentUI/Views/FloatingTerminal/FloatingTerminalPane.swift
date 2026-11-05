import SwiftUI

struct FloatingTerminalPane: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(FloatingTerminalStore.self) private var floating

    let id: UUID
    let isFocused: Bool
    let isSplit: Bool

    private var session: TerminalSession? { floating.session(id) }

    var body: some View {
        VStack(spacing: 0) {
            if isSplit {
                TerminalPaneHeader(title: floating.title(of: id), branch: session?.branch, isFocused: isFocused) { floating.close(id) }
                    .onTapGesture { floating.focus(id) }
                Divider()
            }
            if let session {
                NativeTerminalView(session: session, appearance: settings.terminal, isFocused: isFocused) { floating.focus(id) }
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if session.hasExited {
                    HStack {
                        SessionExitLabel(code: session.exitCode)
                        Spacer()
                        Button("Close") { floating.close(id) }
                        Button("Reopen Terminal") { floating.reopen(id) }
                    }
                    .font(Typography.body).padding(Spacing.l).background(Palette.bar)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { floating.startSession(id) }
    }
}
