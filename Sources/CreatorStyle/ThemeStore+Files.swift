import Foundation

/// Import… and Export…: `.mctheme` files anywhere on disk (Themes milestone).
extension ThemeStore {
    /// Reads the `.mctheme` file at `url` as a new custom theme, saves it and shows it. Its name is the file's (or,
    /// if it has none, the file name's) made unique, so an import never replaces a theme.
    @discardableResult
    public func importTheme(from url: URL) throws(ThemeProblem) -> ColorTheme {
        let refusal = "“\(url.lastPathComponent)” couldn’t be imported."
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeProblem("\(refusal) \(error.localizedDescription)")
        }
        var theme: ColorTheme
        do throws(ThemeFileError) {
            theme = try ThemeFile.decode(data, id: Self.newID(), fallbackName: url.deletingPathExtension().lastPathComponent)
        } catch {
            throw ThemeProblem("\(refusal) \(error.message)")
        }
        theme.name = uniqueName(theme.name)
        try add(theme)
        return theme
    }

    /// Writes the theme with `id`, a built-in or a custom one, to `url` as a `.mctheme` file.
    public func exportTheme(_ id: ColorTheme.ID, to url: URL) throws(ThemeProblem) {
        guard let theme = theme(id) else { throw Self.gone }
        do {
            try ThemeFile.encode(theme).write(to: url, options: .atomic)
        } catch {
            throw ThemeProblem("“\(url.lastPathComponent)” couldn’t be exported. \(error.localizedDescription)")
        }
    }
}
