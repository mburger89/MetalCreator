import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// A double click on a note, or on a frame's title bar, starts editing it in place (comments typing plan; spec
/// 2026-10-09 §8). The recogniser is S5b's: two plain clicks on one target within 0.4 s and 4 points.
@MainActor
struct CommentDoubleClickTests {
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let other = note(3, "Other", at: Vector2(100, 400))
    let frame = box(2, "Bracket", at: Vector2(500, 100))

    func make(dock: DockSide = .bottom) -> (EditorModel, TestClock) {
        let editor = makeEditor([], stickies: [sticky, other], frames: [frame], dock: dock)
        let clock = TestClock()
        editor.now = { clock.now }
        return (editor, clock)
    }

    func body(_ editor: EditorModel, of id: CommentID) -> Vector2 {
        editor.screenPoint(inComment: id, inset: Vector2(40, 40))
    }

    func titleBar(_ editor: EditorModel) -> Vector2 {
        editor.screenPoint(inComment: frame.id, inset: Vector2(60, 10))
    }

    @Test func aDoubleClickOnANoteEditsItsText() throws {
        let (editor, clock) = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        #expect(editor.commentEdit == nil, "one click only selects")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        clock.advance(by: .milliseconds(200))
        editor.click(point + Vector2(2, 1))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == sticky.id && edit.kind == .noteText && edit.draft == "Line one")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        #expect(!editor.document.canUndo, "starting to edit records nothing")
    }

    @Test func aDoubleClickOnAFramesTitleBarEditsItsTitle() throws {
        let (editor, clock) = make()
        editor.click(titleBar(editor))
        clock.advance(by: .milliseconds(200))
        editor.click(titleBar(editor))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == frame.id && edit.kind == .frameTitle && edit.draft == "Bracket")
    }

    /// Review Focus 2: both docks and any pan and zoom, the click points read through the model's own transform.
    @Test func itWorksInBothDocksAtEveryZoom() {
        let transforms = [
            CanvasTransform(),
            CanvasTransform(offset: Vector2(30, 20), zoom: 0.5),
            CanvasTransform(offset: Vector2(-40, 15), zoom: 2),
        ]
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let (editor, clock) = make(dock: dock)
                editor.transform = transform
                for (id, point) in [(sticky.id, body(editor, of: sticky.id)), (frame.id, titleBar(editor))] {
                    editor.click(point)
                    clock.advance(by: .milliseconds(100))
                    editor.click(point)
                    #expect(editor.commentEdit?.id == id, "\(dock) at zoom \(transform.zoom)")
                    editor.cancelCommentEdit()
                    clock.advance(by: .seconds(1))
                }
            }
        }
    }

    /// A frame's edge band is for grabbing the frame, and its inside belongs to the nodes and the box.
    @Test func onlyAFramesTitleBarCounts() {
        let (editor, clock) = make()
        let band = editor.screenPoint(inComment: frame.id, inset: Vector2(3, 150))
        let inside = editor.screenPoint(inComment: frame.id, inset: Vector2(200, 150))
        #expect(editor.hitTest(band) == .frame(frame.id) && editor.hitTest(inside) == .empty)
        for point in [band, inside] {
            editor.click(point)
            clock.advance(by: .milliseconds(100))
            editor.click(point)
            #expect(editor.commentEdit == nil)
            clock.advance(by: .seconds(1))
        }
    }

    /// Review Focus 5: two clicks that aren't a double click (too slow, too far apart, on two comments, a modifier
    /// held, a drag between, or on a selected note's resize handle) never start editing.
    @Test func clicksThatArentADoubleClickDoNothing() throws {
        let (editor, clock) = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        clock.advance(by: .milliseconds(450))
        editor.click(point)
        #expect(editor.commentEdit == nil, "too slow")
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.click(point + Vector2(6, 0))
        #expect(editor.commentEdit == nil, "too far apart")
        clock.advance(by: .seconds(1))
        editor.click(body(editor, of: other.id))
        editor.click(point)
        #expect(editor.commentEdit == nil, "two comments")
        for modifiers: CanvasModifiers in [.shift, .command] {
            clock.advance(by: .seconds(1))
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers)
            #expect(editor.commentEdit == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0))
        #expect(editor.commentEdit == nil, "a drag between")
        clock.advance(by: .seconds(1))
        let moved = try #require(editor.frame(ofComment: sticky.id), "the drag between moved the note")
        let handle = editor.transform.toScreen(CommentLayout.handle(of: moved).centre)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.hitTest(handle) == .resize(sticky.id))
        editor.click(handle)
        editor.click(handle)
        #expect(editor.commentEdit == nil, "the handle resizes")
    }

    @Test func doubleClickingAnotherCommentWhileEditingCommitsTheFirstAndEditsTheNext() {
        let (editor, clock) = make()
        let first = body(editor, of: sticky.id)
        editor.click(first)
        editor.click(first)
        editor.commentDraftChanged("First")
        clock.advance(by: .seconds(1))
        let second = body(editor, of: other.id)
        editor.click(second)
        #expect(editor.graph.stickies[sticky.id]?.text == "First", "the first press committed it")
        #expect(editor.commentEdit == nil)
        clock.advance(by: .milliseconds(100))
        editor.click(second)
        #expect(editor.commentEdit?.id == other.id)
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "the first edit was one undo step")
    }
}
