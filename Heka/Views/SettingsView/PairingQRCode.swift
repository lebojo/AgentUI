import SwiftUI

struct PairingQRCode: View {
    @State private var image: CGImage?

    let content: String

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text("Pairing QR Code"))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Dimension.Settings.pairingCodeSize, height: Dimension.Settings.pairingCodeSize)
                    .padding(Spacing.l)
                    .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: Radius.l))
            }
        }
        .onChange(of: content, initial: true) { _, content in
            image = QRCode.image(encoding: content)
        }
    }
}
