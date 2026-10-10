import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Dragging a type from the node library (a `DragGesture` in window points on its row, no system drag and drop): a
/// release on the canvas adds it at the release point, anywhere else adds nothing, and a press that moves less than
/// `LibraryDrag.threshold` is still a click, adding at the visible centre. Each add is one undo step.
@MainActor
struct LibraryDragTests {
    /// The graph panel docked at the bottom of a 1000 × 700 window, or docked left in a 1400 × 900 one.
    func placed(_ dock: DockSide) -> EditorModel {
        let editor = makeEditor([], dock: dock)
        let placement = dock == .left
            ? PanelPlacement(window: Vector2(1400, 900), panel: CanvasRect(origin: Vector2(12, 68), size: Vector2(460, 820)))
            : PanelPlacement(window: Vector2(1000, 700), panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        editor.placement = { placement }
        return editor
    }

    /// A row's press in window points: inside the library, left of (or above) the canvas.
    func rowPoint(_ editor: EditorModel) throws -> Vector2 {
        let canvas = try #require(editor.canvasFrameInWindow)
        return editor.flow == .horizontal ? Vector2(canvas.origin.x - 100, canvas.origin.y + 40)
                                          : Vector2(canvas.origin.x + 40, canvas.origin.y - 100)
    }

    @Test(arguments: [DockSide.left, .bottom])
    func aReleaseOnTheCanvasAddsTheTypeThereAsOneStep(_ dock: DockSide) throws {
        let editor = placed(dock)
        let canvas = try #require(editor.canvasFrameInWindow)
        let start = try rowPoint(editor), end = canvas.origin + Vector2(120, 60)
        editor.moveLibraryDrag(FilletTestNode.typeID, from: start, to: end)
        #expect(editor.libraryDrag == LibraryDrag(typeID: FilletTestNode.typeID, start: start, location: end))
        #expect(editor.libraryDragEntry?.displayName == "Fillet")
        #expect(editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: end))
        #expect(editor.libraryDrag == nil)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == FilletTestNode.typeID)
        #expect(editor.transform.toScreen(editor.frame(of: added).origin) == Vector2(120, 60), "top-left at the release")
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.document.canUndo, "one step")
    }

    /// The refusal caption sits under the canvas, so a release on it is off the canvas.
    @Test func aReleaseOnTheRefusalCaptionAddsNothing() throws {
        let editor = placed(.bottom)
        let start = try rowPoint(editor)
        let canvas = try #require(editor.canvasFrameInWindow)
        let onCaption = canvas.origin + Vector2(120, canvas.size.y - 4)
        editor.refuse("No.", node: nil)
        #expect(!editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: onCaption))
        #expect(editor.graph.nodes.isEmpty)
        editor.clearRefusal()
        #expect(editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: onCaption), "the same spot is canvas without it")
    }

    /// Released over the library itself, the viewport, the inspector or outside the window: nothing is added.
    @Test(arguments: [DockSide.left, .bottom])
    func aReleaseOffTheCanvasAddsNothing(_ dock: DockSide) throws {
        let editor = placed(dock)
        let start = try rowPoint(editor)
        let window = try #require(editor.panelPlacement).window
        for end in [start + Vector2(12, 12), Vector2(window.x - 20, 30), Vector2(-40, -40), window + Vector2(50, 50)] {
            editor.moveLibraryDrag(ExtrudeTestNode.typeID, from: start, to: end)
            #expect(!editor.endLibraryDrag(ExtrudeTestNode.typeID, from: start, at: end), "released at \(end)")
        }
        #expect(editor.graph.nodes.isEmpty)
        #expect(editor.libraryDrag == nil)
    }

    /// A press that jitters less than the threshold (a trackpad click) is a click: no ghost, and the type is added
    /// at the visible canvas's centre.
    @Test func aClickThatMovesUnderTheThresholdStillAddsAtTheCentre() throws {
        let editor = placed(.bottom)
        let start = try rowPoint(editor), jitter = start + Vector2(6, 7)
        #expect((jitter - start).length < LibraryDrag.threshold)
        editor.moveLibraryDrag(NumberTestNode.typeID, from: start, to: jitter)
        #expect(editor.libraryDrag == nil, "no ghost for a click")
        #expect(editor.endLibraryDrag(NumberTestNode.typeID, from: start, at: jitter))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        let frame = editor.frame(of: added)
        #expect(editor.transform.toScreen(frame.origin + frame.size * 0.5) == editor.visibleCanvasCentre)
        editor.document.undo()
        #expect(!editor.document.canUndo, "one step")
    }

    /// A press dragged out past the threshold and brought back near the press (the usual way to cancel a drag) is
    /// still a drag: released over the library it adds nothing, rather than turning into a click.
    @Test func aDragBroughtBackNearThePressIsStillADragAndAddsNothing() throws {
        let editor = placed(.bottom)
        let start = try rowPoint(editor), out = start + Vector2(100, 0), back = start + Vector2(3, 3)
        editor.moveLibraryDrag(NumberTestNode.typeID, from: start, to: out)
        #expect(editor.libraryDrag != nil)
        editor.moveLibraryDrag(NumberTestNode.typeID, from: start, to: back)
        #expect(editor.libraryDrag == LibraryDrag(typeID: NumberTestNode.typeID, start: start, location: back),
                "the ghost stays, following the pointer")
        #expect(!editor.endLibraryDrag(NumberTestNode.typeID, from: start, at: back))
        #expect(editor.graph.nodes.isEmpty)
        #expect(editor.libraryDrag == nil)
    }

    /// Before the host has placed the panel there is no canvas in window points, so a drag adds nothing; an
    /// unregistered type adds nothing either way.
    @Test func withoutAPlacementOrARegisteredTypeNothingIsAdded() {
        let editor = makeEditor([], dock: .bottom)
        #expect(!editor.endLibraryDrag(NumberTestNode.typeID, from: .zero, at: Vector2(300, 300)))
        let placed = placed(.bottom)
        #expect(!placed.endLibraryDrag("plugin.gone", from: .zero, at: .zero))
        #expect(!placed.endLibraryDrag("plugin.gone", from: .zero, at: Vector2(400, 500)))
        #expect(editor.graph.nodes.isEmpty && placed.graph.nodes.isEmpty)
    }
}
