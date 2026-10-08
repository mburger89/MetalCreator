import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct KeyCommandTests {
    func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func theCanvasKeys() {
        #expect(GraphKeyBindings.command(for: key(" "), paletteOpen: false) == .openPalette)
        #expect(GraphKeyBindings.command(for: key("\t"), paletteOpen: false) == .tab)
        #expect(GraphKeyBindings.command(for: key("\t", .shift), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{7f}"), paletteOpen: false) == .deleteSelection)
        #expect(GraphKeyBindings.command(for: key("\u{f728}"), paletteOpen: false) == .deleteSelection)
        #expect(GraphKeyBindings.command(for: key("c", .command), paletteOpen: false) == .copy)
        #expect(GraphKeyBindings.command(for: key("v", .command), paletteOpen: false) == .paste)
        #expect(GraphKeyBindings.command(for: key("d", .command), paletteOpen: false) == .duplicate)
        #expect(GraphKeyBindings.command(for: key("z", .command), paletteOpen: false) == .undo)
        #expect(GraphKeyBindings.command(for: key("Z", [.command, .shift]), paletteOpen: false) == .redo)
        #expect(GraphKeyBindings.command(for: key("="), paletteOpen: false) == .zoomIn)
        #expect(GraphKeyBindings.command(for: key("+", .shift), paletteOpen: false) == .zoomIn)
        #expect(GraphKeyBindings.command(for: key("-"), paletteOpen: false) == .zoomOut)
        #expect(GraphKeyBindings.command(for: key("c"), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("c", [.command, .option]), paletteOpen: false) == nil)
    }

    @Test func whileThePaletteIsOpenOnlyItsNavigationKeysAreTaken() {
        #expect(GraphKeyBindings.command(for: key("\u{1b}"), paletteOpen: true) == .cancel)
        #expect(GraphKeyBindings.command(for: key("\u{f700}"), paletteOpen: true) == .paletteUp)
        #expect(GraphKeyBindings.command(for: key("\u{f701}"), paletteOpen: true) == .paletteDown)
        #expect(GraphKeyBindings.command(for: key("\r"), paletteOpen: true) == .paletteConfirm)
        #expect(GraphKeyBindings.command(for: key(" "), paletteOpen: true) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{7f}"), paletteOpen: true) == nil)
    }

    @Test func tabOpensThePaletteOverTheCanvasAndOtherwiseTogglesThePanel() {
        let editor = makeEditor([], dock: .left)
        editor.perform(.tab)
        #expect(editor.dock == .hidden)
        editor.perform(.tab)
        #expect(editor.dock == .left)
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.tab)
        #expect(editor.palette != nil)
        #expect(editor.dock == .left)
    }

    @Test func spaceDoesNothingWhileThePanelIsHidden() {
        let editor = makeEditor([], dock: .hidden)
        #expect(!editor.perform(.openPalette))
        #expect(editor.palette == nil)
    }

    @Test func zoomKeysZoomAboutThePointer() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.perform(.zoomIn)
        #expect(editor.transform.zoom == 1.25)
        #expect(editor.transform.toCanvas(Vector2(100, 100)) == Vector2(100, 100))
        editor.perform(.zoomOut)
        #expect(abs(editor.transform.zoom - 1) < 1e-12)
    }

    @Test func undoAndRedoGoThroughTheDocument() {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)])
        editor.selection = [nodeID(1)]
        editor.perform(.deleteSelection)
        #expect(editor.graph.nodes.isEmpty)
        editor.perform(.undo)
        #expect(editor.graph.nodes.count == 1)
        editor.perform(.redo)
        #expect(editor.graph.nodes.isEmpty)
    }

    @Test func deleteWithNothingSelectedLetsTheKeyThrough() {
        let editor = makeEditor([])
        #expect(!editor.perform(.deleteSelection))
        #expect(!editor.perform(.cancel))
    }
}
