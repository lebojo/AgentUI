import SwiftUI

struct DiffSectionHeader: View {
    let section: GitDiffSection

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(section.kind.title).font(Typography.sectionTitle)
            DiffStats(additions: section.additions, deletions: section.deletions)
            Spacer()
            Button("Copy Diff", action: copyPatch)
                .buttonStyle(.borderless).font(Typography.caption)
                .disabled(!section.isComplete)
                .help(section.isComplete ? "Copy this section’s diff" : "Truncated preview: open the file in your editor")
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .background(Palette.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func copyPatch() {
        PlatformClipboard.copy(section.patch)
    }
}
