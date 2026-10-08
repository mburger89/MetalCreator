import CreatorStyle
import Observation
import Testing

/// The theme the app shows: Dracula by default, chosen from the built-ins, remembered through injected
/// preferences (never the real ones in a test), and observable so views re-render.
@MainActor
struct ThemeStoreTests {
    /// Counts observation callbacks.
    @MainActor
    final class Observer {
        var changes = 0
    }

    @Test func itStartsInDraculaWhenNothingIsRemembered() {
        let store = ThemeStore()
        #expect(store.current == .dracula)
        #expect(store.builtIns == ColorTheme.builtIns)
    }

    @Test func selectingAThemeShowsItRemembersItAndTellsObservers() {
        let preferences = InMemoryThemePreferences()
        let store = ThemeStore(preferences: preferences)
        let observer = Observer()
        withObservationTracking { _ = store.current } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        store.select("alucard")
        #expect(store.current == .alucard)
        #expect(preferences.selectedThemeID == "alucard")
        #expect(observer.changes == 1, "a view reading `current` is invalidated")
    }

    @Test func theRememberedThemeIsShownAtStart() {
        #expect(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "nord")).current == .nord)
        #expect(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "gone")).current == .dracula,
                "a remembered theme that no longer exists falls back to Dracula")
    }

    @Test func anUnknownThemeIsIgnored() {
        let preferences = InMemoryThemePreferences(selectedThemeID: "nord")
        let store = ThemeStore(preferences: preferences)
        store.select("solarized")
        #expect(store.current == .nord)
        #expect(preferences.selectedThemeID == "nord")
    }
}
