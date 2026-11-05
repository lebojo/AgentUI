import SwiftUI

struct TerminalFooter: View {
    let session: TerminalSession?
    let path: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "folder").foregroundStyle(Palette.textSecondary)
            Text((session?.currentDirectory ?? path).abbreviatingHome)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: Spacing.l)
            Text("⌘T  New Terminal   ⌘D  Split").foregroundStyle(Palette.textSecondary)
        }
        .font(Typography.s).foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.xl).frame(height: Dimension.Detail.footerHeight)
    }
}
