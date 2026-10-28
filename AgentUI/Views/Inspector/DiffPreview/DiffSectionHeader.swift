import AppKit
import SwiftUI

struct DiffSectionHeader: View {
    let section: GitDiffSection

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(section.kind.title).font(Typography.sectionTitle)
            DiffStats(additions: section.additions, deletions: section.deletions)
            Spacer()
            Button("Copier le diff", action: copyPatch)
                .buttonStyle(.borderless).font(Typography.caption)
                .disabled(!section.isComplete)
                .help(section.isComplete ? "Copier le diff de cette section" : "Aperçu tronqué : ouvre le fichier dans ton éditeur")
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .background(Palette.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func copyPatch() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.patch, forType: .string)
    }
}
