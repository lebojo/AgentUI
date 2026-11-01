import SwiftUI

struct InspectorPreviewPresenter: ViewModifier {
    @Bindable var previews: InspectorPreviews

    let source: any InspectorSource

    func body(content: Content) -> some View {
        content
            .task(id: previews.request) {
                await previews.load(readFile: { try await source.textFile($0) }, readDiff: { try await source.diff($0, at: $1) })
            }
            .sheet(item: $previews.current) { preview in
                switch preview {
                case .file(let file): TextPreviewSheet(preview: file, source: source)
                case .diff(let diff): DiffPreviewSheet(diff: diff)
                }
            }
            .alert("Preview Unavailable", isPresented: $previews.error.isPresent) {
                Button("OK") { previews.error = nil }
            } message: { Text(previews.error ?? "") }
    }
}
