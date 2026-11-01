import SwiftUI

struct TextPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: TextPreview
    let source: any InspectorSource

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preview.title).font(Typography.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if source.canOpenLocalFiles, let url = preview.url {
                    Button("Open") { source.openLocalFile(url) }
                }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(preview.text).font(Typography.code)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding()
            }.background(Palette.surface)
        }.previewSheetFrame(idealWidth: Dimension.PreviewSheet.idealWidth, idealHeight: Dimension.PreviewSheet.idealHeight)
    }
}
