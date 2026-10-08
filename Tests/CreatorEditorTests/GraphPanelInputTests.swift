import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct GraphPanelInputTests {
    @Test func modifierChangesReachTheModelWithoutBeingClaimed() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(!input.handle(.modifiersChanged([.shift, .option])))
        #expect(editor.modifiers == [.shift, .option])
        #expect(!input.handle(.modifiersChanged([])))
        #expect(editor.modifiers.isEmpty)
    }

    @Test func mappedKeysAreRunAndClaimed() {
        let node = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([node])
        editor.selection = [node.id]
        let input = GraphPanelInput(model: editor)
        let delete = KeyEvent(charactersIgnoringModifiers: "\u{7f}", characters: "\u{7f}", timestamp: 1)
        #expect(input.handle(.keyDown(delete)))
        #expect(editor.graph.nodes.isEmpty)
        let letter = KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 2)
        #expect(!input.handle(.keyDown(letter)))
    }

    @Test func hoverTracksThePointer() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        input.hover(.active(Point(x: Pixels(12), y: Pixels(34))))
        #expect(editor.pointerLocation == Vector2(12, 34))
        input.hover(.ended)
        #expect(editor.pointerLocation == nil)
    }

    /// The window keymap runs before a focused field's editing keys, so the palette's arrows
    /// are bound there. Only the mapping is pinned here: tests can't build a real `Window`.
    @Test func paletteArrowsAreKeymapActionsOnlyWhileThePaletteIsOpen() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(GraphPanelInput.keymap.bindings.map(\.spelling) == ["up", "down", "tab"])
        #expect(GraphPanelInput.keymap.bindings.prefix(2).allSatisfy { $0.action is PaletteMove })
        // Closed: unhandled, so MetalUI passes the arrow on to a focused field.
        #expect(!input.handleAction(PaletteMove(step: 1)))
        editor.openPalette()
        #expect(input.handleAction(PaletteMove(step: 1)))
        #expect(editor.palette?.highlighted == 1)
        #expect(input.handleAction(PaletteMove(step: -1)))
        #expect(editor.palette?.highlighted == 0)
    }

    /// Tab is a keymap action because Tab focus traversal runs before `onInput` whenever anything
    /// focusable is on screen (the inspector always is). Unclaimed, it falls through to traversal
    /// or, while hidden, to `GraphShowButton`'s shortcut. Only the mapping is pinned here.
    @Test func tabIsAKeymapActionThatOpensThePaletteOnlyOverTheVisibleCanvas() throws {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        let binding = try #require(GraphPanelInput.keymap.bindings.last)
        #expect(binding.spelling == "tab")
        #expect(binding.action is GraphTab)
        // Pointer off the canvas: unclaimed, so focus traversal gets Tab.
        #expect(!input.handleAction(GraphTab()))
        #expect(editor.palette == nil)
        input.hover(.active(Point(x: Pixels(40), y: Pixels(30))))
        #expect(input.handleAction(GraphTab()))
        #expect(editor.palette?.screenPosition == Vector2(40, 30))
        // Palette already open: unclaimed (no second palette).
        #expect(!input.handleAction(GraphTab()))
        editor.closePalette()
        // Hidden: unclaimed, so `GraphShowButton`'s Tab shortcut shows the panel.
        editor.toggleHidden()
        #expect(!editor.isPanelVisible)
        #expect(!input.handleAction(GraphTab()))
        #expect(editor.palette == nil)
    }

    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var releases = 0
        input.releaseTextFocus = { releases += 1 }
        input.canvasChanged(from: Vector2(10, 10), to: Vector2(10, 10))
        input.canvasChanged(from: Vector2(10, 10), to: Vector2(40, 10))
        input.canvasEnded(from: Vector2(10, 10), at: Vector2(40, 10))
        #expect(releases == 1)
        input.canvasEnded(from: Vector2(5, 5), at: Vector2(5, 5))
        #expect(releases == 2)
        #expect(editor.transform.offset == Vector2(30, 0))
    }

    /// The C7 stand-ins are single functions named after C7's provisional APIs, so the swap is local.
    @Test func theC7StandInsAreTheirOwnFunctions() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(GraphPanelInput.spatialTapGesture().minimumDistance == Pixels(0))
        _ = input.handle(.modifiersChanged([.option]))
        let value = DragGesture.Value(startLocation: Point(x: Pixels(1), y: Pixels(2)), location: Point(x: Pixels(3), y: Pixels(4)))
        #expect(input.dragValueModifiers(value) == .option)
    }
}
