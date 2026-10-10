import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the canvas with comments (canvas comments spec 2026-10-09 §7): frames draw behind notes and
/// notes behind nodes, the selected last within their kind; ghosts draw under repeated-looking IDs; views stay cheap.
@MainActor
struct CommentRenderTests {
    func canvasOrigin(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary).origin
    }

    /// The top-left of the rect painted last at `point` (display canvas points), in canvas points.
    func painted(at point: Vector2, in scene: Scene, _ editor: EditorModel) -> Vector2? {
        let origin = canvasOrigin(editor)
        return topRect(at: origin + point, in: scene).map { screenFrame(of: $0, in: scene).origin - origin }
    }

    func panel(_ editor: EditorModel) -> Scene {
        renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
    }

    @Test func framesDrawBehindNotesAndNotesBehindNodes() {
        let node = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
        let sticky = note(1, at: Vector2(60, 120), size: Vector2(160, 100))
        let frame = box(1, at: Vector2(40, 40), size: Vector2(500, 400))
        let editor = makeEditor([node], stickies: [sticky], frames: [frame])
        let scene = panel(editor)
        #expect(painted(at: Vector2(500, 400), in: scene, editor) == Vector2(40, 40), "the frame, where nothing is above it")
        #expect(painted(at: Vector2(80, 200), in: scene, editor) == Vector2(60, 120), "the note beats the frame")
        #expect(painted(at: Vector2(120, 140), in: scene, editor) == Vector2(100, 100), "the node beats the note")
    }

    @Test func selectedCommentsDrawLastWithinTheirKind() {
        let back = note(1, at: Vector2(300, 100)), front = note(2, at: Vector2(340, 120))
        let editor = makeEditor([], stickies: [back, front])
        #expect(painted(at: Vector2(360, 140), in: panel(editor), editor) == Vector2(340, 120))
        editor.canvasSelection = CanvasSelection(comments: [back.id])
        #expect(painted(at: Vector2(360, 140), in: panel(editor), editor) == Vector2(300, 100), "the selected note is raised")
        let low = box(3, at: Vector2(20, 300), size: Vector2(300, 200)), high = box(4, at: Vector2(60, 340), size: Vector2(300, 200))
        let frames = makeEditor([], frames: [low, high])
        #expect(painted(at: Vector2(200, 450), in: panel(frames), frames) == Vector2(60, 340))
        frames.canvasSelection = CanvasSelection(comments: [low.id])
        #expect(painted(at: Vector2(200, 450), in: panel(frames), frames) == Vector2(20, 300))
    }

    @Test func aSelectedCommentShowsItsHandleInTheBottomRightCorner() {
        let sticky = note(1, at: Vector2(100, 100))
        let editor = makeEditor([], stickies: [sticky])
        let corner = Vector2(254, 194)
        #expect(painted(at: corner, in: panel(editor), editor) == Vector2(100, 100))
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(painted(at: corner, in: panel(editor), editor) == Vector2(248, 188), "the 12 point handle")
    }

    @Test func commentsDrawInTheLeftDockAtTheirTranspose() {
        let sticky = note(1, at: Vector2(100, 300))  // drawn at (300, 100), 100 × 160
        let editor = makeEditor([], stickies: [sticky], dock: .left)
        #expect(painted(at: Vector2(380, 240), in: panel(editor), editor) == Vector2(300, 100))
    }

    @Test func ghostsOfCommentsWhoseIDsPrintAlikeAllDraw() {
        let notes = (1...2).map { note($0, at: Vector2(Double($0) * 200, 100)) }
        let frames = box(3, at: Vector2(20, 300), size: Vector2(200, 100))
        #expect(Set((notes.map(\.id) + [frames.id]).map(\.description)).count == 1, "set up: the test IDs print alike")
        let editor = makeEditor([], stickies: notes, frames: [frames])
        editor.canvasSelection = CanvasSelection(comments: [notes[0].id, notes[1].id, frames.id])
        let start = editor.screenPoint(inComment: notes[0].id, inset: Vector2(20, 20))
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200), modifiers: .option)
        let ghosts = CanvasLayers.commentGhosts(editor)
        #expect(ghosts.notes.count == 2 && ghosts.frames.count == 1)
        #expect(ghosts.notes.map(\.frame.origin) == [Vector2(200, 300), Vector2(400, 300)])
        let scene = panel(editor)
        for ghost in ghosts.notes {
            #expect(painted(at: ghost.frame.origin + Vector2(80, 50), in: scene, editor) == ghost.frame.origin)
        }
        #expect(CanvasLayers.commentGhosts(makeEditor([])).notes.isEmpty)
    }

    /// PERF-b: a comment is a handful of primitives (fill, border, and with a selection the handle), not a tree.
    @Test func eachCommentIsAFewRects() {
        let none = panel(makeEditor([])).rects.count
        let sticky = note(1, at: Vector2(100, 100)), frame = box(2, at: Vector2(300, 100))
        let editor = makeEditor([], stickies: [sticky], frames: [frame])
        let plain = panel(editor).rects.count - none
        editor.canvasSelection = CanvasSelection(comments: [sticky.id, frame.id])
        let selected = panel(editor).rects.count - none
        #expect(plain <= 6 && plain >= 4, "unselected: a fill and a border each, and the frame's title bar (\(plain))")
        #expect(selected - plain == 2, "selected: one handle each (\(selected - plain))")
    }

    /// Text and titles of any length draw inside their comment without trapping: very long, many lines, no spaces.
    @Test func extremeTextStillRenders() {
        let long = String(repeating: "wide", count: 5_000)
        let lines = (0..<400).map { "line \($0)" }.joined(separator: "\n")
        let editor = makeEditor([], stickies: [note(1, long, at: Vector2(20, 20)), note(2, lines, at: Vector2(300, 20)),
                                               note(3, "", at: Vector2(20, 200), size: Vector2(0, 0)), ],
                                frames: [box(4, long, at: Vector2(20, 300)),
                                         box(5, "", at: Vector2(500, 300), size: Vector2(10, 10)), ])
        editor.canvasSelection = editor.allItems
        #expect(!panel(editor).rects.isEmpty)
        #expect(editor.hitTest(Vector2(25, 205)) == .empty, "a zero-size note can't be hit, and can be selected with ⌘A")
    }

    @Test func aGraphOfManyCommentsStillRenders() {
        let notes = (1...200).map { note($0, at: Vector2(Double($0 % 20) * 170, Double($0 / 20) * 110)) }
        let editor = makeEditor([], stickies: notes)
        let area = CanvasRect(origin: Vector2(12, 288), size: Vector2(876, 300))
        editor.placement = { PanelPlacement(window: Vector2(900, 600), panel: area) }
        #expect(editor.drawnNotes.count < notes.count, "culled to what shows")
        #expect(!panel(editor).rects.isEmpty)
    }
}
