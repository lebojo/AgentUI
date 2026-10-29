import SwiftUI

struct InspectorPreviewPresenter: ViewModifier {
    @Bindable var previews: InspectorPreviews

    func body(content: Content) -> some View {
        content
            .task(id: previews.request) { await previews.load() }
            .sheet(item: $previews.current) { preview in
                switch preview {
                case .file(let file): TextPreviewSheet(preview: file)
                case .diff(let diff): DiffPreviewSheet(diff: diff)
                }
            }
            .alert("Aperçu indisponible", isPresented: $previews.error.isPresent) {
                Button("OK") { previews.error = nil }
            } message: { Text(previews.error ?? "") }
    }
}
