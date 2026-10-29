import Foundation
import Observation

@MainActor @Observable final class InspectorPreviews {
    enum Request: Equatable, Sendable {
        case file(URL)
        case diff(GitChange, root: String)

        func load() async throws -> InspectorPreview {
            switch self {
            case .file(let url): .file(TextPreview(title: url.lastPathComponent, text: try await InspectorService.textFile(url), url: url))
            case .diff(let change, let root): .diff(try await InspectorService.diff(change, at: root))
            }
        }
    }

    var current: InspectorPreview?
    var error: String?
    private(set) var request: Request?

    var isLoading: Bool { request != nil }

    func open(_ url: URL) { submit(.file(url)) }

    func diff(_ change: GitChange, at root: String) { submit(.diff(change, root: root)) }

    func load() async {
        guard let request else { return }
        do { current = try await request.load() }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
        self.request = nil
    }

    private func submit(_ request: Request) {
        guard self.request == nil else { return }
        self.request = request
    }
}
