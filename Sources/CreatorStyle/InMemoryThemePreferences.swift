/// Theme preferences that last as long as the object: every test's, and any store that shouldn't remember.
@MainActor
public final class InMemoryThemePreferences: ThemePreferences {
    public var selectedThemeID: ColorTheme.ID?

    public init(selectedThemeID: ColorTheme.ID? = nil) {
        self.selectedThemeID = selectedThemeID
    }
}
