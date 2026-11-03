import AppKit

enum MonospacedFonts {
    @MainActor static let families: [String] = NSFontManager.shared.availableFontFamilies.filter { family in
        NSFont(name: family, size: 13)?.isFixedPitch ?? false
    }
}
