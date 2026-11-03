extension TerminalAppearance {
    func previewing(_ theme: TerminalTheme) -> TerminalAppearance {
        var preview = self
        preview.theme = theme
        return preview
    }
}
