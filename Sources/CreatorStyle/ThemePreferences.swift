/// Where the chosen theme's id is remembered between launches. Injected into `ThemeStore`, so tests never touch
/// the real preferences. M6 ships only `InMemoryThemePreferences` (the app starts in Dracula each launch); the
/// Themes milestone after M6 adds one backed by the user's defaults.
@MainActor
public protocol ThemePreferences: AnyObject {
    var selectedThemeID: ColorTheme.ID? { get set }
}
