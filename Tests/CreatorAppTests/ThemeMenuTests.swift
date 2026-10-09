import CreatorStyle
import Testing
@testable import CreatorApp

/// View ▸ Theme lists the built-ins, then the custom themes by name, each group divided from the next.
@MainActor
struct ThemeMenuTests {
    @Test func withoutCustomThemesTheMenuListsTheBuiltIns() {
        #expect(ThemeMenu.sections(ThemeStore()) == [ColorTheme.builtIns])
    }

    @Test func customThemesFollowTheBuiltInsByName() throws {
        let store = ThemeStore()
        let zebra = try store.duplicate("nord")
        try store.rename(zebra.id, to: "Zebra")
        try store.duplicate("alucard")
        #expect(ThemeMenu.sections(store).map { $0.map(\.name) } == [["Dracula", "Alucard", "Nord"], ["Alucard Copy", "Zebra"]])
        try store.delete(zebra.id)
        #expect(ThemeMenu.sections(store).map { $0.map(\.name) } == [["Dracula", "Alucard", "Nord"], ["Alucard Copy"]])
    }
}
