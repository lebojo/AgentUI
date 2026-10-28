import SwiftUI
import AppKit

struct ExplorerDirectory: View {
    let url: URL
    let open: (URL) -> Void
    @State private var entries: [ExplorerEntry] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let error { InspectorNotice(title: "Dossier inaccessible", message: error) }
            else if !loaded { ProgressView().controlSize(.small) }
            else if entries.isEmpty { Text("Dossier vide").font(Typography.caption).foregroundStyle(Palette.textSecondary) }
            ForEach(entries) { entry in
                ExplorerRow(entry: entry, open: open)
            }
        }
        .task(id: url) {
            do {
                let result = try await InspectorService.children(at: url)
                guard !Task.isCancelled else { return }
                entries = result; loaded = true; error = nil
            } catch { self.error = error.localizedDescription; loaded = true }
        }
    }
}

private struct ExplorerRow: View {
    let entry: ExplorerEntry
    let open: (URL) -> Void
    @State private var expanded = false
    var body: some View {
        Group {
            if entry.isDirectory {
                DisclosureGroup(isExpanded: $expanded) {
                    if expanded { ExplorerDirectory(url: entry.url, open: open) }
                } label: { Label(entry.name, systemImage: "folder").lineLimit(1) }
            } else {
                Button { open(entry.url) } label: {
                    Label(entry.name, systemImage: entry.isSymbolicLink ? "link" : "doc")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .font(Typography.body).help(entry.url.path)
        .contextMenu {
            Button("Ouvrir dans l’application par défaut") { NSWorkspace.shared.open(entry.url) }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
    }
}

struct TextPreviewSheet: View {
    let preview: TextPreview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preview.title).font(Typography.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let url = preview.url {
                    Button("Ouvrir") { NSWorkspace.shared.open(url) }
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(preview.text).font(Typography.code)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding()
            }.background(Palette.surface)
        }.frame(minWidth: Dimension.PreviewSheet.minWidth, idealWidth: Dimension.PreviewSheet.idealWidth, minHeight: Dimension.PreviewSheet.minHeight, idealHeight: Dimension.PreviewSheet.idealHeight)
    }
}
