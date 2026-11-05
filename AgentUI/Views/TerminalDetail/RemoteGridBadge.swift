import SwiftUI

struct RemoteGridBadge: View {
    let session: TerminalSession

    var body: some View {
        if session.remoteGrid != nil {
            HStack(spacing: Spacing.m) {
                Label("Sized for Mobile", systemImage: "iphone").foregroundStyle(Palette.textSecondary)
                Button("Use Mac Size") { session.usedLocally() }.buttonStyle(.link)
            }
            .font(Typography.s)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
            .containerShape(Capsule())
            .glassBackground()
            .padding(Spacing.m)
            .help("A phone is viewing this terminal at its own size, so part of it may be hidden here.")
        }
    }
}
