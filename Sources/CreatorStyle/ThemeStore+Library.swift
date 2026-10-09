import Foundation

/// Custom themes (Themes milestone): duplicate any theme, then rename, recolour, darken or delete the copy. The
/// built-ins stay read-only (spec §6.6). Every change is saved before it is shown, so a save that fails changes
/// nothing and says why.
extension ThemeStore {
    /// Duplicate: a custom copy of the theme with `id` named "<name> Copy" (then "… Copy 2" and on), saved and shown.
    @discardableResult
    public func duplicate(_ id: ColorTheme.ID) throws(ThemeProblem) -> ColorTheme {
        guard let source = theme(id) else { throw Self.gone }
        let copy = ColorTheme(id: Self.newID(), name: uniqueName(source.name + " Copy"), isDark: source.isDark,
                              colors: source.colors.quantized)
        try add(copy)
        return copy
    }

    /// Renames a custom theme. The name is trimmed; an empty name, or one another theme has (in any case), is refused.
    public func rename(_ id: ColorTheme.ID, to name: String) throws(ThemeProblem) {
        var theme = try editable(id)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThemeProblem("A theme needs a name.") }
        guard trimmed != theme.name else { return }
        guard !isTaken(trimmed, except: id) else { throw ThemeProblem("There’s already a theme called “\(trimmed)”.") }
        theme.name = trimmed
        try replace(theme)
    }

    /// Sets one role's colour in a custom theme, quantized as its file will hold it. Shown at once if it is current.
    public func setColor(_ color: HexColor, for role: ThemeRole, in id: ColorTheme.ID) throws(ThemeProblem) {
        var theme = try editable(id)
        let color = color.quantized
        guard theme.colors[role] != color else { return }
        theme.colors[role] = color
        try replace(theme)
    }

    /// Whether a custom theme asks for MetalUI's dark controls (and the window's dark appearance) or its light ones.
    public func setDark(_ isDark: Bool, in id: ColorTheme.ID) throws(ThemeProblem) {
        var theme = try editable(id)
        guard theme.isDark != isDark else { return }
        theme.isDark = isDark
        try replace(theme)
    }

    /// Deletes a custom theme and its file. If it was shown, Dracula is shown and remembered instead.
    public func delete(_ id: ColorTheme.ID) throws(ThemeProblem) {
        _ = try editable(id)
        try folder?.remove(id)
        customs.removeAll { $0.id == id }
        if current.id == id {
            current = .dracula
            preferences.selectedThemeID = ColorTheme.dracula.id
        }
    }

    /// The custom theme with `id`. A built-in is refused (read-only), and so is a theme that is gone.
    func editable(_ id: ColorTheme.ID) throws(ThemeProblem) -> ColorTheme {
        guard !isBuiltIn(id) else { throw ThemeProblem("Built-in themes can’t be changed. Duplicate one to make your own.") }
        guard let theme = customs.first(where: { $0.id == id }) else { throw Self.gone }
        return theme
    }

    /// Saves a new custom theme, then lists and shows it.
    func add(_ theme: ColorTheme) throws(ThemeProblem) {
        try folder?.save(theme)
        customs = Self.sorted(customs + [theme])
        select(theme.id)
    }

    /// Saves a changed custom theme, then lists it and, if it is current, shows the change.
    func replace(_ theme: ColorTheme) throws(ThemeProblem) {
        try folder?.save(theme)
        customs = Self.sorted(customs.map { $0.id == theme.id ? theme : $0 })
        if current.id == theme.id { current = theme }
    }

    /// `base`, or `base` followed by the first free number from 2.
    func uniqueName(_ base: String) -> String {
        guard isTaken(base) else { return base }
        var number = 2
        while isTaken("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Whether a theme other than `id` is called `name`, ignoring case.
    func isTaken(_ name: String, except id: ColorTheme.ID? = nil) -> Bool {
        themes.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A new custom theme's id, which is also its file's name.
    static func newID() -> ColorTheme.ID { "custom-" + UUID().uuidString.lowercased() }

    static var gone: ThemeProblem { ThemeProblem("That theme no longer exists.") }
}
