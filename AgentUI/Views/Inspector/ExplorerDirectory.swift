import SwiftUI

struct ExplorerDirectory: View {
    @State private var entries: [ExplorerEntry] = []
    @State private var omitted = 0
    @State private var error: String?
    @State private var loaded = false

    let url: URL
    let source: any InspectorSource

    var body: some View {
        Group {
            if let error { InspectorNotice(title: "Dossier inaccessible", message: error) }
            else if !loaded { ProgressView().controlSize(.small) }
            else if entries.isEmpty { Text("Dossier vide").font(Typography.caption).foregroundStyle(Palette.textSecondary) }
            ForEach(entries) { entry in
                ExplorerRow(entry: entry, source: source)
            }
            if omitted > 0 {
                InspectorNotice(title: "Liste tronquée", message: "\(omitted) autres éléments non affichés sur cet appareil", symbol: "ellipsis.circle")
            }
        }
        .task(id: url) {
            do {
                let result = try await source.children(at: url)
                guard !Task.isCancelled else { return }
                entries = result.entries; omitted = result.omitted; loaded = true; error = nil
            } catch { self.error = error.localizedDescription; loaded = true }
        }
    }
}

private struct ExplorerRow: View {
    @Environment(InspectorPreviews.self) private var previews

    @State private var expanded = false

    let entry: ExplorerEntry
    let source: any InspectorSource

    var body: some View {
        Group {
            if entry.isDirectory {
                DisclosureGroup(isExpanded: $expanded) {
                    if expanded { ExplorerDirectory(url: entry.url, source: source) }
                } label: { Label(entry.name, systemImage: "folder").lineLimit(1) }
            } else {
                Button { previews.open(entry.url) } label: {
                    Label(entry.name, systemImage: entry.isSymbolicLink ? "link" : "doc")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .font(Typography.body).help(entry.url.path)
        .contextMenu {
            if source.canOpenLocalFiles {
                Button("Ouvrir dans l’application par défaut") { source.openLocalFile(entry.url) }
                Button("Afficher dans le Finder") { source.revealLocalFile(entry.url) }
            }
        }
    }
}

struct TextPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: TextPreview
    let source: any InspectorSource

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preview.title).font(Typography.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if source.canOpenLocalFiles, let url = preview.url {
                    Button("Ouvrir") { source.openLocalFile(url) }
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(preview.text).font(Typography.code)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding()
            }.background(Palette.surface)
        }.previewSheetFrame(idealWidth: Dimension.PreviewSheet.idealWidth, idealHeight: Dimension.PreviewSheet.idealHeight)
    }
}
