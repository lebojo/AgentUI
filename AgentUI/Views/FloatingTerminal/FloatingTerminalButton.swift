import SwiftUI

struct FloatingTerminalButton: View {
    @Environment(FloatingTerminalStore.self) private var floating

    var body: some View {
        Button("Floating Terminal", systemImage: "apple.terminal") { floating.isPresented = true }
            .labelStyle(.iconOnly)
            .help("Floating Terminal (⇧⌘T)")
            .accessibilityLabel("Show floating terminal")
    }
}
