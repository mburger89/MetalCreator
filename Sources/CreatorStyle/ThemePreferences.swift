/// Where the chosen theme's id is remembered between launches. Injected into `ThemeStore`, so tests never touch
/// the real preferences: the app uses `UserDefaultsThemePreferences`, tests `InMemoryThemePreferences` or a defaults
/// suite of their own.
@MainActor
public protocol ThemePreferences: AnyObject {
    var selectedThemeID: ColorTheme.ID? { get set }
}
