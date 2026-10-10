import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the canvas while a note or a frame's title is being typed into in place (comments typing plan;
/// spec 2026-10-09 §8): the field lies over the comment, in either dock and at any pan and zoom, and it is opaque, so
/// the text under it doesn't show through.
@MainActor
struct CommentEditorRenderTests {
    let sticky = note(1, "Line one", at: Vector2(100, 60))
    let frame = box(2, "Bracket", at: Vector2(50, 200), size: Vector2(300, 150))
    let transforms = [
        CanvasTransform(),
        CanvasTransform(offset: Vector2(10, 5), zoom: 0.5),
        CanvasTransform(offset: Vector2(-30, 15), zoom: 2),
    ]

    func canvasOrigin(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary).origin
    }

    func panel(_ editor: EditorModel) -> Scene {
        renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
    }

    /// The rect painted last at `displayPoint` (display canvas points), as a frame in window points.
    func painted(at displayPoint: Vector2, in scene: Scene, _ editor: EditorModel) -> (frame: CanvasRect, opaque: Bool)? {
        let point = canvasOrigin(editor) + editor.transform.toScreen(displayPoint)
        return topRect(at: point, in: scene).map { (screenFrame(of: $0, in: scene), $0.background.a == 1) }
    }

    func editor(dock: DockSide, _ transform: CanvasTransform) -> EditorModel {
        let editor = makeEditor([], stickies: [sticky], frames: [frame], dock: dock)
        editor.transform = transform
        return editor
    }

    /// Review Focus 2: both docks, three zooms; the field is exactly the note's rectangle through the canvas's own
    /// transform, and opaque where the note's tint is not.
    @Test func theNoteEditorLiesExactlyOverTheNote() throws {
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let editor = editor(dock: dock, transform)
                let rect = try #require(editor.frame(ofComment: sticky.id))
                let inside = rect.origin + Vector2(10, 10)
                let before = try #require(painted(at: inside, in: panel(editor), editor))
                #expect(!before.opaque, "set up: the note is a tint")
                editor.beginEditing(sticky.id)
                let during = try #require(painted(at: inside, in: panel(editor), editor))
                let origin = canvasOrigin(editor) + transform.toScreen(rect.origin)
                let size = rect.size * transform.zoom
                #expect(during.opaque, "\(dock), zoom \(transform.zoom)")
                #expect((during.frame.origin - origin).length < 0.51 && (during.frame.size - size).length < 0.51,
                        "\(dock), zoom \(transform.zoom): \(during.frame) against \(origin) \(size)")
            }
        }
    }

    @Test func theTitleEditorLiesInsideTheTitleBar() throws {
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let editor = editor(dock: dock, transform)
                let bar = CommentLayout.titleBar(of: try #require(editor.frame(ofComment: frame.id)))
                let inside = bar.origin + Vector2(30, bar.size.y * 0.5)
                let before = try #require(painted(at: inside, in: panel(editor), editor))
                #expect(!before.opaque, "set up: the bar is a tint")
                editor.beginEditing(frame.id)
                let during = try #require(painted(at: inside, in: panel(editor), editor))
                let origin = canvasOrigin(editor) + transform.toScreen(bar.origin)
                let size = bar.size * transform.zoom
                #expect(during.opaque, "\(dock), zoom \(transform.zoom)")
                #expect(during.frame.origin.x >= origin.x - 0.51 && during.frame.maxX <= origin.x + size.x + 0.51)
                #expect(during.frame.origin.y >= origin.y - 0.51 && during.frame.maxY <= origin.y + size.y + 0.51,
                        "\(dock), zoom \(transform.zoom): \(during.frame) in \(origin) \(size)")
            }
        }
    }

    /// The layer builds nothing without an edit (views stay cheap, PERF-b): the frame is what it was when the comment
    /// was merely selected, once the edit has ended either way.
    @Test func noFieldIsBuiltWithoutAnEdit() {
        let editor = editor(dock: .bottom, CanvasTransform())
        for id in [sticky.id, frame.id] {
            editor.canvasSelection = CanvasSelection(comments: [id])
            let selected = panel(editor).rects.count
            editor.beginEditing(id)
            #expect(panel(editor).rects.count > selected)
            editor.cancelCommentEdit()
            #expect(panel(editor).rects.count == selected)
            editor.beginEditing(id)
            editor.commitCommentEdit()
            #expect(panel(editor).rects.count == selected)
        }
    }
}
