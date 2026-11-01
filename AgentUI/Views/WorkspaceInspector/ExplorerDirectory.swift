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
