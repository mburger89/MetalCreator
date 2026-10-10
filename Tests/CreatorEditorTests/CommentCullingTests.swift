import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// The canvas builds only the comments that can show, as it does nodes (canvas comments spec 2026-10-09 §7;
/// `EditorModel.drawnCanvasRect`); hit testing, selection and edits always see them all.
@MainActor
struct CommentCullingTests {
    static let window = Vector2(1000, 700)
    static let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))

    func placed(_ editor: EditorModel) -> EditorModel {
        editor.placement = { PanelPlacement(window: Self.window, panel: Self.panel) }
        return editor
    }

    @Test func anUnplacedPanelDrawsEveryComment() {
        let editor = makeEditor([], stickies: [note(1), note(2, at: Vector2(9_000, 9_000))],
                                frames: [box(3), box(4, at: Vector2(-9_000, 0))])
        #expect(editor.drawnNotes.map(\.id) == editor.drawOrderNotes.map(\.id))
        #expect(editor.drawnFrames.map(\.id) == editor.drawOrderFrames.map(\.id))
    }

    @Test func commentsWhollyOutsideTheDrawnRectAreNotBuilt() {
        let near = note(1, at: Vector2(100, 100)), far = note(2, at: Vector2(5_000, 100))
        let framedNear = box(3, at: Vector2(50, 50)), framedFar = box(4, at: Vector2(100, 3_000))
        let editor = placed(makeEditor([], stickies: [near, far], frames: [framedNear, framedFar]))
        #expect(editor.drawnNotes.map(\.id) == [near.id])
        #expect(editor.drawnFrames.map(\.id) == [framedNear.id])
        #expect(editor.drawOrderNotes.count == 2 && editor.drawOrderFrames.count == 2, "the model keeps them all")
        #expect(editor.hitTest(Vector2(5_010, 110)) == .note(far.id), "hit testing never culls")
    }

    @Test func aFrameBiggerThanTheViewIsBuiltWhileAnyPartShows() {
        let huge = box(1, at: Vector2(-4_000, -4_000), size: Vector2(8_000, 8_000))
        let editor = placed(makeEditor([], frames: [huge]))
        #expect(editor.drawnFrames.map(\.id) == [huge.id])
    }

    @Test func aPanBringsACommentIntoView() {
        let far = note(1, at: Vector2(5_000, 100))
        let editor = placed(makeEditor([], stickies: [far]))
        #expect(editor.drawnNotes.isEmpty)
        editor.transform = CanvasTransform(offset: Vector2(-4_900, 0), zoom: 1)
        #expect(editor.drawnNotes.map(\.id) == [far.id])
    }

    @Test func theLeftDockCullsByTheDrawnTranspose() {
        let sticky = note(1, at: Vector2(5_000, 100))  // drawn at (100, 5000)
        let editor = placed(makeEditor([], stickies: [sticky], dock: .left))
        #expect(editor.drawnNotes.isEmpty)
        editor.transform = CanvasTransform(offset: Vector2(0, -4_900), zoom: 1)
        #expect(editor.drawnNotes.map(\.id) == [sticky.id])
    }
}
