import Foundation

extension InspectorStore {
    @discardableResult func perform(_ action: GitAction, at root: String, with source: any InspectorSource) async -> Bool {
        await perform(action, at: root) { try await source.perform($0, at: $1) }
    }
}
