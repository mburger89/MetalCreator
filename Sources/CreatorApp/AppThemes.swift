import CreatorStyle

/// The app's themes (Themes milestone): the chosen one remembered in the person's defaults, their own themes in
/// `~/Library/Application Support/MetalCreator/Themes`. Only the app makes this store; tests and previews make
/// theirs with in-memory preferences and no folder.
public enum AppThemes {
    @MainActor
    public static func store() -> ThemeStore {
        ThemeStore(preferences: UserDefaultsThemePreferences(), folder: .applicationSupport)
    }
}
