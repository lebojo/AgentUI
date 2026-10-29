import Foundation
import Observation

@MainActor @Observable final class InspectorPreviews {
    var current: InspectorPreview?
    var error: String?
    private(set) var isLoading = false

    func open(_ url: URL) {
        load { .file(TextPreview(title: url.lastPathComponent, text: try await InspectorService.textFile(url), url: url)) }
    }

    func diff(_ change: GitChange, at root: String) {
        load { .diff(try await InspectorService.diff(change, at: root)) }
    }

    private func load(_ preview: @escaping @Sendable () async throws -> InspectorPreview) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do { current = try await preview() }
            catch { self.error = error.localizedDescription }
        }
    }
}
