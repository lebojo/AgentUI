import SwiftUI

struct ExplorerRow: View {
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
                Button("Open with Default App") { source.openLocalFile(entry.url) }
                Button("Show in Finder") { source.revealLocalFile(entry.url) }
            }
        }
    }
}
