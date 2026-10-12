import CreatorStyle
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing
@testable import CreatorApp

/// What View ▸ Theme lists, which item is checked and what choosing one does, read from the evaluated menu itself
/// (gap TH-a): `MenuEvaluation` evaluates `ThemeMenu.items` as a window would at the menu's open, and the app's menu
/// bar (`AppCommands`) is read and run through `TestApp.menuBar`.
@MainActor
struct ThemeMenuEvaluationTests {
    /// Titles of the evaluated items, with a separator as "-".
    func titles(_ items: [PlatformMenuItem]) -> [String] {
        items.map { item in
            if case .separator = item.kind { "-" } else { item.title }
        }
    }

    func customThemes() throws -> ThemeStore {
        let store = ThemeStore()
        let zebra = try store.duplicate("nord")
        try store.rename(zebra.id, to: "Zebra")
        try store.duplicate("alucard")
        return store
    }

    @Test func withoutCustomThemesTheMenuListsTheBuiltInsThenEditThemes() {
        let menu = MenuEvaluation { ThemeMenu.items(ThemeEditorModel(themes: ThemeStore())) }
        #expect(titles(menu.items) == ["Dracula", "Alucard", "Nord", "-", "Edit Themes…"])
    }

    @Test func customThemesFollowTheBuiltInsDividedFromThemAndFromEditThemes() throws {
        let editor = ThemeEditorModel(themes: try customThemes())
        let menu = MenuEvaluation { ThemeMenu.items(editor) }
        #expect(titles(menu.items) == ["Dracula", "Alucard", "Nord", "-", "Alucard Copy", "Zebra", "-", "Edit Themes…"])
    }

    @Test func theShownThemeAloneIsChecked() throws {
        let store = ThemeStore()
        let editor = ThemeEditorModel(themes: store)
        let checked = MenuEvaluation { ThemeMenu.items(editor) }.items.filter(\.isOn).map(\.title)
        #expect(checked == [store.current.name])
        editor.select("nord")
        let afterwards = MenuEvaluation { ThemeMenu.items(editor) }.items.filter(\.isOn).map(\.title)
        #expect(afterwards == ["Nord"])
    }

    @Test func choosingAThemeShowsItAtOnceAndEditThemesOpensTheEditor() throws {
        let editor = ThemeEditorModel(themes: ThemeStore())
        let menu = MenuEvaluation { ThemeMenu.items(editor) }
        try menu.perform("Alucard")
        #expect(editor.theme.name == "Alucard")
        #expect(!editor.isOpen)
        try menu.perform("Edit Themes…")
        #expect(editor.isOpen)
    }

    // MARK: - The app's menu bar

    /// Every rect's fill, in draw order: what a theme change repaints.
    func fills(_ scene: Scene) -> [[Float]] {
        scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    }

    func themeSubmenu(_ app: AppWindow) throws -> [PlatformMenuItem] {
        let view = try #require(app.testApp.menuBar.first { $0.title == "View" })
        guard case .submenu(let items)? = view.items.first(where: { $0.title == "Theme" })?.kind else {
            Issue.record("View has no Theme submenu")
            return []
        }
        return items
    }

    @Test func theMenuBarHasViewThemeWithTheShownThemeChecked() async throws {
        let app = try await AppWindow.open()
        let items = try themeSubmenu(app)
        #expect(titles(items) == ["Dracula", "Alucard", "Nord", "-", "Edit Themes…"])
        #expect(items.filter(\.isOn).map(\.title) == [app.model.themes.current.name])
    }

    @Test func choosingAThemeInTheMenuBarRestylesTheWindow() async throws {
        let app = try await AppWindow.open()
        let before = fills(app.window.scene)
        try app.testApp.performMenuBarItem("View", "Theme", "Alucard")
        #expect(app.model.themes.current.name == "Alucard")
        #expect(try themeSubmenu(app).filter(\.isOn).map(\.title) == ["Alucard"])
        #expect(fills(app.window.scene) != before, "the frame drawn after the choice is in the new theme")
        try app.testApp.performMenuBarItem("View", "Theme", "Edit Themes…")
        #expect(app.themeEditor.isOpen)
    }
}
