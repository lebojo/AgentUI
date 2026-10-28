import SwiftUI

struct TerminalPreview: View {
    let appearance: TerminalAppearance

    private var ansi: [Color] { appearance.ansi }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("~/agentui ").foregroundStyle(ansi[4]) + Text("main").foregroundStyle(ansi[5])
            Text("❯ ").foregroundStyle(ansi[2]) + Text("git status --short").foregroundStyle(appearance.foreground)
            Text(" M ").foregroundStyle(ansi[1]) + Text("AgentUI/Views/TerminalDetail.swift").foregroundStyle(appearance.foreground)
            Text("A  ").foregroundStyle(ansi[2]) + Text("AgentUI/Views/Settings/").foregroundStyle(appearance.foreground)
            Text("✓ ").foregroundStyle(ansi[10]) + Text("Build réussi en 4,2 s").foregroundStyle(ansi[8])
            Text("❯ ").foregroundStyle(ansi[2]) + Text("claude").foregroundStyle(appearance.foreground) + Text("█").foregroundStyle(appearance.cursor)
        }
        .font(appearance.font)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(appearance.background, in: RoundedRectangle(cornerRadius: Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Palette.fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du terminal avec le thème \(appearance.theme.title)")
    }
}
