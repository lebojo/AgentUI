import Foundation
import Observation

@MainActor @Observable final class InspectorPreviews {
    enum Request: Equatable, Sendable {
        case file(URL)
        case diff(GitChange, root: String)

    }

    @ObservationIgnored private let readFile: @Sendable (URL) async throws -> String
    @ObservationIgnored private let readDiff: @Sendable (GitChange, String) async throws -> GitDiff

    init(readFile: @escaping @Sendable (URL) async throws -> String,
         readDiff: @escaping @Sendable (GitChange, String) async throws -> GitDiff) {
        self.readFile = readFile
        self.readDiff = readDiff
    }

    var current: InspectorPreview?
    var error: String?
    private(set) var request: Request?

    var isLoading: Bool { request != nil }

    func open(_ url: URL) { submit(.file(url)) }

    func diff(_ change: GitChange, at root: String) { submit(.diff(change, root: root)) }

    func load() async {
        guard let request else { return }
        do {
            switch request {
            case .file(let url): current = .file(TextPreview(title: url.lastPathComponent, text: try await readFile(url), url: url))
            case .diff(let change, let root): current = .diff(try await readDiff(change, root))
            }
        }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
        self.request = nil
    }

    private func submit(_ request: Request) {
        guard self.request == nil else { return }
        self.request = request
    }
}
