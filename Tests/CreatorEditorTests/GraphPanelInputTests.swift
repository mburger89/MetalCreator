import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct GraphPanelInputTests {
    /// A canvas drag value as MetalUI reports it, in canvas-local points.
    func value(_ start: Vector2, _ location: Vector2, _ modifiers: Modifiers = []) -> DragGesture.Value {
        DragGesture.Value(startLocation: Point(x: Pixels(Float(start.x)), y: Pixels(Float(start.y))),
                          location: Point(x: Pixels(Float(location.x)), y: Pixels(Float(location.y))),
                          modifiers: modifiers)
    }

    /// The window's modifier events are neither claimed nor kept: a press reads its own (MetalUI C7), so a ⇧
    /// reported while the pointer was elsewhere can't make the next click extend the selection.
    @Test func modifierChangesAreNeitherClaimedNorTracked() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(!input.handle(.modifiersChanged([.shift, .option])))
        let point = editor.screenPoint(in: b.id)
        input.canvasChanged(value(point, point))
        input.canvasEnded(value(point, point))
        #expect(editor.selection == [b.id])
    }

    /// The canvas gesture starts at the press (zero minimum distance), and each value's modifiers reach the model:
    /// the press's ⇧ extends the click, and control is dropped (the canvas binds nothing to it).
    @Test func theCanvasGestureReadsThePressModifiersFromItsValues() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(input.canvasGesture().minimumDistance == Pixels(0))
        let point = editor.screenPoint(in: b.id)
        input.canvasChanged(value(point, point, [.shift, .control]))
        input.canvasEnded(value(point, point))
        #expect(editor.selection == [a.id, b.id])
        #expect(GraphPanelInput.canvasModifiers([.shift, .option, .command, .control]) == [.shift, .option, .command])
    }

    @Test func anOptionDragThroughTheGestureDuplicates() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        let input = GraphPanelInput(model: editor)
        let start = editor.screenPoint(in: a.id)
        input.canvasChanged(value(start, start, .option))
        input.canvasChanged(value(start, start + Vector2(0, 80), .option))
        input.canvasEnded(value(start, start + Vector2(0, 80), .option))
        #expect(editor.graph.nodes.count == 2)
        #expect(editor.graph.nodes[a.id]?.position == .zero)
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

    @Test func scrollEventsMapToCanvasPhases() {
        func event(_ phase: InputPhase, momentum: InputPhase = .none) -> ScrollEvent {
            ScrollEvent(position: Point(x: Pixels(0), y: Pixels(0)), delta: Point(x: Pixels(0), y: Pixels(1)),
                        phase: phase, momentumPhase: momentum, isPrecise: true, timestamp: 0)
        }
        #expect(GraphPanelInput.scrollPhase(of: event(.none)) == .step)
        #expect(GraphPanelInput.scrollPhase(of: event(.mayBegin)) == .began)
        #expect(GraphPanelInput.scrollPhase(of: event(.began)) == .began)
        #expect(GraphPanelInput.scrollPhase(of: event(.changed)) == .changed)
        #expect(GraphPanelInput.scrollPhase(of: event(.ended)) == .ended)
        #expect(GraphPanelInput.scrollPhase(of: event(.cancelled)) == .ended)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .began)) == .momentum)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .changed)) == .momentum)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .ended)) == .momentumEnded)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .cancelled)) == .momentumEnded)
    }

    /// A scroll is claimed and reaches the model at the canvas-local `location`, not the window's `position`.
    @Test func aScrollEventZoomsAboutItsLocalPoint() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var event = ScrollEvent(position: Point(x: Pixels(700), y: Pixels(500)), delta: Point(x: Pixels(0), y: Pixels(10)),
                                modifiers: .command, phase: .none, momentumPhase: .none, isPrecise: false, timestamp: 0)
        event.location = Point(x: Pixels(200), y: Pixels(100))
        let under = editor.transform.toCanvas(Vector2(200, 100))
        #expect(input.scrolled(event))
        #expect(editor.transform.zoom > 1)
        #expect((editor.transform.toCanvas(Vector2(200, 100)) - under).length < 1e-6)
    }

    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var releases = 0
        input.releaseTextFocus = { releases += 1 }
        input.canvasChanged(value(Vector2(10, 10), Vector2(10, 10)))
        input.canvasChanged(value(Vector2(10, 10), Vector2(40, 10)))
        input.canvasEnded(value(Vector2(10, 10), Vector2(40, 10)))
        #expect(releases == 1)
        input.canvasEnded(value(Vector2(5, 5), Vector2(5, 5)))
        #expect(releases == 2)
        #expect(editor.transform.offset == Vector2(30, 0))
    }
}
