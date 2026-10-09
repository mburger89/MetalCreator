import Foundation

/// The chosen theme's id in the person's defaults (Themes milestone), so the app starts in the theme it was left
/// in. The app passes `.standard`; tests pass a suite of their own and remove it.
@MainActor
public final class UserDefaultsThemePreferences: ThemePreferences {
    /// The defaults key.
    public static let key = "selectedThemeID"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedThemeID: ColorTheme.ID? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
