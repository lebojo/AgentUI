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
                HStack(spacing: Spacing.s) {
                    Image(systemName: "terminal").foregroundStyle(isFocused ? Palette.accent : Palette.textSecondary)
                    Text(floating.title(of: id)).lineLimit(1)
                        .foregroundStyle(isFocused ? Palette.textPrimary : Palette.textSecondary)
                    if let branch = session?.branch {
                        BranchBadge(branch: branch).frame(maxWidth: Dimension.Badge.sidebarMaxWidth)
                    }
                    Spacer(minLength: Spacing.xs)
                    Button { floating.close(id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Close This Pane")
                        .accessibilityLabel("Close terminal \(floating.title(of: id))")
                }
                .font(Typography.s).padding(.horizontal, Spacing.l).frame(height: Dimension.Detail.paneTitleHeight)
                .background(isFocused ? Palette.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { floating.focus(id) }
                Divider()
            }
            if let session {
                NativeTerminalView(session: session, appearance: settings.terminal, isFocused: isFocused) { floating.focus(id) }
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: session.hasExited) { _, hasExited in
                        if hasExited { floating.close(id) }
                    }
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
