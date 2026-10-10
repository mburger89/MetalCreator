import Foundation
import Observation

/// The app's themes and the one it shows (spec §6.6: themeable, Dracula by default). Views read `current` through
/// the environment and the app shell hands it to the viewport, so selecting a theme, or editing the current one,
/// re-renders the editor by observation and reaches the GPU colours on the viewport's next frame. The built-ins are
/// read-only; the person's own themes (`customs`) are duplicated, renamed, recoloured, deleted, imported and
/// exported here (`ThemeStore+Library`, `ThemeStore+Files`), and each change is saved to `folder` at once (except a
/// colour drag, which is shown first and saved once: `previewColor`, `saveColors()`).
@MainActor
@Observable
public final class ThemeStore {
    /// The read-only themes, in menu order.
    public let builtIns: [ColorTheme]
    /// The person's own themes, by name.
    public internal(set) var customs: [ColorTheme]
    /// The theme shown now.
    public internal(set) var current: ColorTheme
    /// One sentence for each file in the themes folder that couldn't be read at launch (the theme editor shows them).
    public let loadProblems: [String]
    @ObservationIgnored let preferences: any ThemePreferences
    /// Where custom themes are saved; `nil` keeps them in memory only (tests, previews).
    @ObservationIgnored let folder: ThemeFolder?
    /// A custom theme as it was last saved, while colours changed with `previewColor` wait to be saved (`saveColors()`).
    @ObservationIgnored var unsavedBase: ColorTheme?

    /// Loads the custom themes from `folder`, then starts with the theme `preferences` remembers, or Dracula when it
    /// remembers none or one that no longer exists.
    public init(preferences: any ThemePreferences = InMemoryThemePreferences(), builtIns: [ColorTheme] = ColorTheme.builtIns,
                folder: ThemeFolder? = nil) {
        self.preferences = preferences
        self.builtIns = builtIns
        self.folder = folder
        let loaded = folder?.load(reserved: Set(builtIns.map(\.id))) ?? (themes: [], problems: [])
        let customs = Self.sorted(loaded.themes)
        self.customs = customs
        loadProblems = loaded.problems
        current = (builtIns + customs).first { $0.id == preferences.selectedThemeID } ?? .dracula
    }

    /// Every theme in menu order: the built-ins, then the custom themes.
    public var themes: [ColorTheme] { builtIns + customs }

    /// The theme with `id`, or `nil`.
    public func theme(_ id: ColorTheme.ID) -> ColorTheme? { themes.first { $0.id == id } }

    /// Whether `id` is a read-only built-in.
    public func isBuiltIn(_ id: ColorTheme.ID) -> Bool { builtIns.contains { $0.id == id } }

    /// Shows the theme with `id` and remembers it. An id no theme has is ignored.
    public func select(_ id: ColorTheme.ID) {
        guard let theme = theme(id) else { return }
        preferences.selectedThemeID = id
        if theme != current { current = theme }
    }

    /// Custom themes in menu order: by name as Finder sorts, then by id.
    static func sorted(_ themes: [ColorTheme]) -> [ColorTheme] {
        themes.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}
