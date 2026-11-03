import SwiftUI

struct UsageProviderLogo: View {
    let provider: UsageProvider
    let size: CGFloat

    var body: some View {
        provider.logo
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Palette.textPrimary)
            .accessibilityHidden(true)
    }
}

private extension UsageProvider {
    var logo: Image {
        switch self {
        case .claude: Image(.claudeLogo)
        case .codex: Image(.codexLogo)
        }
    }
}
