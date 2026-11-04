import SwiftUI

struct GitActionButton: View {
    @Environment(InspectorStore.self) private var model

    let action: GitAction
    let root: String
    let source: any InspectorSource

    var body: some View {
        Button {
            Task { await model.perform(action, at: root, with: source) }
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
        .help(action.title)
    }
}
