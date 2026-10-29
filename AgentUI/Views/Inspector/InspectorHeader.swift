import SwiftUI

struct InspectorHeader: View {
    @Environment(InspectorPreviews.self) private var previews

    @Binding var refresh: Int

    let model: InspectorStore
    let title: String
    let subtitle: String
    let path: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(Typography.headline)
                Text(subtitle)
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(1).help(path)
            }
            Spacer()
            if model.loading || previews.isLoading { ProgressView().controlSize(.small) }
            Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Actualiser").accessibilityLabel("Actualiser \(title)")
        }.padding(Spacing.l)
    }
}
