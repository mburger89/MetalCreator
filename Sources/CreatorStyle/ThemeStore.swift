import Observation

/// The theme the app shows (spec §6.6: themeable, Dracula by default). Views read `current` through the
/// environment and the app shell hands it to the viewport, so selecting a theme re-renders the editor by
/// observation and reaches the GPU colours on the viewport's next frame.
@MainActor
@Observable
public final class ThemeStore {
    /// The read-only themes, in menu order.
    public let builtIns: [ColorTheme]
    /// The theme shown now.
    public private(set) var current: ColorTheme
    @ObservationIgnored private let preferences: any ThemePreferences

    /// Starts with the theme `preferences` remembers, or Dracula when it remembers none or one that no longer
    /// exists.
    public init(preferences: any ThemePreferences = InMemoryThemePreferences(), builtIns: [ColorTheme] = ColorTheme.builtIns) {
        self.preferences = preferences
        self.builtIns = builtIns
        current = builtIns.first { $0.id == preferences.selectedThemeID } ?? .dracula
    }

    /// Shows the theme with `id` and remembers it. An id no theme has is ignored.
    public func select(_ id: ColorTheme.ID) {
        guard let theme = builtIns.first(where: { $0.id == id }) else { return }
        preferences.selectedThemeID = id
        if theme != current { current = theme }
    }
}
