import SwiftUI

struct GitActionFailureNotice: View {
    @Environment(InspectorStore.self) private var model

    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            InspectorNotice(title: "Git Action Failed", message: message)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark") { model.actionFailure = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
    }
}
