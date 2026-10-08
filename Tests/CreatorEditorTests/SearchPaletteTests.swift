import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct SearchPaletteTests {
    @Test func anEmptyQueryListsEveryTypeByCategoryThenName() {
        let names = PaletteSearch.entries(in: editorTestRegistry, matching: "").map(\.displayName)
        #expect(names == ["Number", "Rectangle", "Extrude", "All Edges", "Fillet", "Output"])
    }

    @Test func queriesMatchAnywhereIgnoringCaseAndPrefixesComeFirst() {
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "EDGE").map(\.displayName) == ["All Edges"])
        // "e" prefixes Extrude and appears inside the others.
        let names = PaletteSearch.entries(in: editorTestRegistry, matching: "e").map(\.displayName)
        #expect(names.first == "Extrude")
        #expect(Set(names) == ["Extrude", "Number", "Rectangle", "All Edges", "Fillet"])
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "zzz").isEmpty)
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "  fil ").map(\.displayName) == ["Fillet"])
    }

    @Test func thePaletteOpensUnderThePointer() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(120, 80)
        editor.openPalette()
        #expect(editor.palette == SearchPaletteState(screenPosition: Vector2(120, 80)))
    }

    @Test func confirmingAddsTheHighlightedTypeUnderThePaletteAndSelectsIt() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(200, 100)
        editor.openPalette()
        editor.setPaletteQuery("t")
        #expect(editor.paletteEntries.map(\.displayName) == ["Rectangle", "Extrude", "Fillet", "Output"])
        editor.movePaletteHighlight(by: 1)
        editor.confirmPalette()
        #expect(editor.palette == nil)
        let added = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(added?.typeID == ExtrudeTestNode.typeID)
        #expect(added?.position == Vector2(200, 100))
    }

    @Test func theHighlightStaysWithinTheMatches() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.movePaletteHighlight(by: -3)
        #expect(editor.palette?.highlighted == 0)
        editor.movePaletteHighlight(by: 50)
        #expect(editor.palette?.highlighted == 5)
        editor.setPaletteQuery("out")
        #expect(editor.palette?.highlighted == 0)
    }

    @Test func confirmingWithNoMatchesKeepsThePaletteOpen() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.setPaletteQuery("zzz")
        editor.confirmPalette()
        #expect(editor.palette != nil)
        #expect(editor.graph.nodes.isEmpty)
    }

    @Test func pressingTheCanvasClosesThePalette() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.click(Vector2(50, 50))
        #expect(editor.palette == nil)
    }
}
