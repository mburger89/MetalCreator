import CreatorStyle
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// The theme editor's behaviour: it edits the shown theme through `ThemeStore`, keeps a typed name with the theme
/// it was typed for, asks before deleting, and shows each problem as one sentence.
@MainActor
struct ThemeEditorModelTests {
    func makeEditor(_ store: ThemeStore = ThemeStore()) -> ThemeEditorModel {
        ThemeEditorModel(themes: store)
    }

    @Test func openingShowsTheFoldersProblemsAndDoneCloses() throws {
        let folder = ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeEditorModelTests-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        let editor = makeEditor(ThemeStore(folder: folder))
        #expect(!editor.isOpen)
        editor.open()
        #expect(editor.isOpen)
        #expect(editor.message == "“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged.")
        editor.close()
        #expect(!editor.isOpen)
    }

    @Test func theBuiltInsAreShownButNotEditable() throws {
        let editor = makeEditor()
        #expect(editor.theme == .dracula && !editor.isEditable)
        editor.setColor(HexColor(0x000000), for: try #require(ThemeRole.named("accent")))
        #expect(editor.message == "Built-in themes can’t be changed. Duplicate one to make your own.")
        #expect(editor.theme == .dracula)
        editor.requestDelete()
        #expect(!editor.isConfirmingDelete)
    }

    @Test func duplicateMakesAnEditableCopyAndClearsTheMessage() throws {
        let editor = makeEditor()
        editor.setDark(false)
        #expect(editor.message != nil)
        editor.duplicate()
        #expect(editor.theme.name == "Dracula Copy" && editor.isEditable && editor.message == nil)
        editor.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("selection")))
        #expect(editor.theme.colors.selection == HexColor(0x00ffaa))
    }

    @Test func aTypedNameIsCommittedOnReturn() {
        let editor = makeEditor()
        editor.duplicate()
        editor.typeName("Midnight")
        #expect(editor.nameText == "Midnight" && editor.theme.name == "Dracula Copy")
        editor.commitName()
        #expect(editor.theme.name == "Midnight" && editor.nameText == "Midnight")
    }

    /// Review focus: a name typed, then another theme chosen from View ▸ Theme before Return: the name lands on the
    /// theme it was typed for, and the field shows the new theme's own name.
    @Test func aTypedNameStaysWithItsTheme() throws {
        let editor = makeEditor()
        editor.duplicate()
        let copy = editor.theme
        editor.typeName("Midnight")
        editor.themes.select("nord")
        #expect(editor.nameText == "Nord")
        editor.commitName()
        #expect(editor.themes.theme(copy.id)?.name == "Midnight")
        #expect(editor.theme == .nord)
    }

    @Test func aRefusedNameSaysWhyAndTheFieldShowsTheName() {
        let editor = makeEditor()
        editor.duplicate()
        editor.typeName("nord")
        editor.commitName()
        #expect(editor.message == "There’s already a theme called “nord”.")
        #expect(editor.nameText == "Dracula Copy")
    }

    @Test func closingAndSelectingCommitATypedName() {
        let editor = makeEditor()
        editor.open()
        editor.duplicate()
        let copy = editor.theme
        editor.typeName("Dusk")
        editor.select("alucard")
        #expect(editor.themes.theme(copy.id)?.name == "Dusk" && editor.theme == .alucard)
        editor.select(copy.id)
        editor.typeName("Dawn")
        editor.close()
        #expect(editor.themes.theme(copy.id)?.name == "Dawn")
    }

    @Test func deleteAsksFirst() {
        let editor = makeEditor()
        editor.duplicate()
        let copy = editor.theme
        editor.requestDelete()
        #expect(editor.isConfirmingDelete)
        editor.isConfirmingDelete = false
        #expect(editor.themes.theme(copy.id) != nil)
        editor.requestDelete()
        #expect(editor.deleteTitle == "Delete “Dracula Copy”?")
        editor.confirmDelete()
        #expect(!editor.isConfirmingDelete && editor.themes.theme(copy.id) == nil && editor.theme == .dracula)
    }

    /// Delete… asked about one theme, then another was chosen from View ▸ Theme while the confirmation was up: the
    /// confirmation still names the first, and Delete removes that one, never the one shown now.
    @Test func aDeleteConfirmationStaysWithItsTheme() {
        let editor = makeEditor()
        editor.duplicate()
        let first = editor.theme
        editor.select("nord")
        editor.duplicate()
        let second = editor.theme
        editor.select(first.id)
        editor.requestDelete()
        editor.select(second.id)
        #expect(editor.isConfirmingDelete && editor.deleteTitle == "Delete “Dracula Copy”?")
        editor.confirmDelete()
        #expect(editor.themes.theme(first.id) == nil)
        #expect(editor.themes.theme(second.id) == second && editor.theme == second)
    }

    /// The colour picker's binding reads the shown theme and writes through `setColor`.
    @Test func theColourBindingReadsAndWritesTheRole() throws {
        let editor = makeEditor()
        editor.duplicate()
        let accent = try #require(ThemeRole.named("accent"))
        let binding = editor.colorBinding(for: accent)
        #expect(HexColor(binding.wrappedValue) == HexColor(0xbd93f9))
        binding.wrappedValue = Color(.sRGB, red: 0, green: 1, blue: 2.0 / 3)
        #expect(editor.theme.colors.accent == HexColor(0x00ffaa))
    }

    @Test func importAsksForAThemeFileAndShowsTheImport() async throws {
        let url = temporaryURL("Fjord.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try ThemeStore().exportTheme("nord", to: url)
        let editor = makeEditor()
        let picker = ScriptedPicker([url])
        await editor.importTheme(using: picker)
        #expect(picker.asked.map(\.types) == [[.mctheme]])
        #expect(editor.theme.name == "Nord 2" && editor.isEditable && editor.message == nil)
    }

    @Test func aCancelledImportChangesNothing() async {
        let editor = makeEditor()
        await editor.importTheme(using: ScriptedPicker([nil]))
        #expect(editor.themes.customs.isEmpty && editor.theme == .dracula && editor.message == nil)
    }

    @Test func aRefusedImportIsShown() async throws {
        let url = temporaryURL("bad.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: url)
        let editor = makeEditor()
        await editor.importTheme(using: ScriptedPicker([url]))
        #expect(editor.message == "“\(url.lastPathComponent)” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6.")
    }

    @Test func exportWritesTheShownThemeUnderItsName() async throws {
        let url = temporaryURL("Nord.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let editor = makeEditor(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "nord")))
        let picker = ScriptedPicker([url])
        await editor.exportTheme(using: picker)
        #expect(picker.asked.map(\.name) == ["Nord.mctheme"])
        #expect(try ThemeFile.decode(Data(contentsOf: url), id: "x", fallbackName: "").colors == ColorTheme.nord.colors.quantized)
    }
}
