import SwiftUI

struct DiffPreviewSheet: View {
    @AppStorage("diffLayout") private var layout: DiffLayout = .unified

    @Environment(\.dismiss) private var dismiss

    let diff: GitDiff

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(diff.path).font(Typography.headline).lineLimit(1).truncationMode(.middle).help(diff.path)
                    if let section = diff.onlySection {
                        DiffStats(additions: section.additions, deletions: section.deletions)
                    }
                }
                Spacer()
                Picker("Affichage du diff", selection: $layout) {
                    ForEach(DiffLayout.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            if diff.sections.isEmpty {
                ContentUnavailableView("Aucun diff", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Aucun diff disponible pour ce fichier."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(diff.sections) { section in
                            Section {
                                rows(section)
                            } header: {
                                DiffSectionHeader(section: section)
                            }
                        }
                    }.textSelection(.enabled)
                }.background(Palette.surface)
            }
        }
        .frame(minWidth: Dimension.PreviewSheet.minWidth, idealWidth: Dimension.DiffSheet.idealWidth,
               minHeight: Dimension.PreviewSheet.minHeight, idealHeight: Dimension.DiffSheet.idealHeight)
    }

    @ViewBuilder private func rows(_ section: GitDiffSection) -> some View {
        switch layout {
        case .unified: ForEach(section.lines) { UnifiedDiffRow(line: $0, digits: diff.lineNumberDigits) }
        case .split: ForEach(section.rows) { SplitDiffRow(row: $0, digits: diff.lineNumberDigits) }
        }
    }
}
