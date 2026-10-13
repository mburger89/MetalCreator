import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// A double click on a note, or on a frame's title bar, starts editing it in place (comments typing plan; spec
/// 2026-10-09 §8). The recogniser is S5b's: two plain clicks on one target, the second counted 2 by the platform.
@MainActor
struct CommentDoubleClickTests {
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let other = note(3, "Other", at: Vector2(100, 400))
    let frame = box(2, "Bracket", at: Vector2(500, 100))

    func make(dock: DockSide = .bottom) -> EditorModel {
        makeEditor([], stickies: [sticky, other], frames: [frame], dock: dock)
    }

    func body(_ editor: EditorModel, of id: CommentID) -> Vector2 {
        editor.screenPoint(inComment: id, inset: Vector2(40, 40))
    }

    func titleBar(_ editor: EditorModel) -> Vector2 {
        editor.screenPoint(inComment: frame.id, inset: Vector2(60, 10))
    }

    @Test func aDoubleClickOnANoteEditsItsText() throws {
        let editor = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        #expect(editor.commentEdit == nil, "one click only selects")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        editor.click(point + Vector2(2, 1), clickCount: 2)
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == sticky.id && edit.kind == .noteText && edit.draft == "Line one")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        #expect(!editor.document.canUndo, "starting to edit records nothing")
    }

    @Test func aDoubleClickOnAFramesTitleBarEditsItsTitle() throws {
        let editor = make()
        editor.click(titleBar(editor))
        editor.click(titleBar(editor), clickCount: 2)
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
                let editor = make(dock: dock)
                editor.transform = transform
                for (id, point) in [(sticky.id, body(editor, of: sticky.id)), (frame.id, titleBar(editor))] {
                    editor.doubleClick(point)
                    #expect(editor.commentEdit?.id == id, "\(dock) at zoom \(transform.zoom)")
                    editor.cancelCommentEdit()
                }
            }
        }
    }

    /// A frame's edge band is for grabbing the frame, and its inside belongs to the nodes and the box.
    @Test func onlyAFramesTitleBarCounts() {
        let editor = make()
        let band = editor.screenPoint(inComment: frame.id, inset: Vector2(3, 150))
        let inside = editor.screenPoint(inComment: frame.id, inset: Vector2(200, 150))
        #expect(editor.hitTest(band) == .frame(frame.id) && editor.hitTest(inside) == .empty)
        for point in [band, inside] {
            editor.doubleClick(point)
            #expect(editor.commentEdit == nil)
        }
    }

    /// Review Focus 5: two clicks that aren't a double click (the platform counted the second as a new first click, on
    /// two comments, a modifier held, a drag between, or on a selected note's resize handle) never start editing.
    @Test func clicksThatArentADoubleClickDoNothing() throws {
        let editor = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        editor.click(point)
        #expect(editor.commentEdit == nil, "too slow or too far for the platform: both count 1")
        editor.click(body(editor, of: other.id))
        editor.click(point, clickCount: 2)
        #expect(editor.commentEdit == nil, "two comments")
        for modifiers: CanvasModifiers in [.shift, .command] {
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers, clickCount: 2)
            #expect(editor.commentEdit == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0), clickCount: 2)
        #expect(editor.commentEdit == nil, "a drag between")
        let moved = try #require(editor.frame(ofComment: sticky.id), "the drag between moved the note")
        let handle = editor.transform.toScreen(CommentLayout.handle(of: moved).centre)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.hitTest(handle) == .resize(sticky.id))
        editor.doubleClick(handle)
        #expect(editor.commentEdit == nil, "the handle resizes")
    }

    @Test func doubleClickingAnotherCommentWhileEditingCommitsTheFirstAndEditsTheNext() {
        let editor = make()
        let first = body(editor, of: sticky.id)
        editor.doubleClick(first)
        editor.commentDraftChanged("First")
        let second = body(editor, of: other.id)
        editor.click(second)
        #expect(editor.graph.stickies[sticky.id]?.text == "First", "the first press committed it")
        #expect(editor.commentEdit == nil)
        editor.click(second, clickCount: 2)
        #expect(editor.commentEdit?.id == other.id)
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "the first edit was one undo step")
    }
}
