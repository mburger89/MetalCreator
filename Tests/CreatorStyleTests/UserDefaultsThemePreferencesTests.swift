import CreatorStyle
import Foundation
import Testing

/// The chosen theme is remembered in the person's defaults: here a suite of the test's own, removed afterwards.
@MainActor
struct UserDefaultsThemePreferencesTests {
    /// A fresh defaults suite and its name, for `removePersistentDomain(forName:)`.
    static func suite() throws -> (defaults: UserDefaults, name: String) {
        let name = "MetalCreatorTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func itRemembersTheChosenThemeAcrossInstances() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserDefaultsThemePreferences(defaults: defaults)
        #expect(preferences.selectedThemeID == nil)
        preferences.selectedThemeID = "nord"
        #expect(UserDefaultsThemePreferences(defaults: defaults).selectedThemeID == "nord")
        #expect(defaults.string(forKey: UserDefaultsThemePreferences.key) == "nord")
        preferences.selectedThemeID = nil
        #expect(UserDefaultsThemePreferences(defaults: defaults).selectedThemeID == nil)
    }

    @Test func theStoreStartsInTheThemeItWasLeftIn() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).select("alucard")
        #expect(ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).current == .alucard)
    }

    @Test func aRememberedValueThatIsntAThemeShowsDracula() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(42, forKey: UserDefaultsThemePreferences.key)
        #expect(ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).current == .dracula)
    }
}
