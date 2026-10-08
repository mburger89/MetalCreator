/// Theme preferences that last as long as the object: the app's until the Themes milestone, and every test's.
@MainActor
public final class InMemoryThemePreferences: ThemePreferences {
    public var selectedThemeID: ColorTheme.ID?

    public init(selectedThemeID: ColorTheme.ID? = nil) {
        self.selectedThemeID = selectedThemeID
    }
}
