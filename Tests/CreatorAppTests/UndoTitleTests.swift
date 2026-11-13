import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorApp

/// The Edit menu and the top bar read "Undo <name>" and "Redo <name>" (named undo steps; parent spec §6.1). The views
/// show `AppModel.undoTitle` and `redoTitle`, so the titles are pinned on the model.
@MainActor
struct UndoTitleTests {
    @Test func withNothingToUndoOrRedoTheTitlesArePlain() async {
        let app = await makeApp()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo")
    }

    @Test func theTitlesNameTheStepsAndFollowUndoAndRedo() async throws {
        let app = await makeApp()
        app.editor.addNote(atScreen: Vector2(30, 40))
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo")
        let note = try #require(app.editor.graph.stickies.keys.first)
        app.editor.canvasSelection = CanvasSelection(comments: [note])
        app.editor.deleteSelection()
        #expect(app.undoTitle == "Undo Delete")
        app.undo()
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo Delete")
        app.undo()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo Add Note")
        app.redo()
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo Delete")
    }

    @Test func anInputEditIsTitledByTheInputsLabel() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        guard case .slider(let field, _)? = app.editor.inspectorPage.sections.first?.rows.dropFirst().first else {
            Issue.record("no Distance slider"); return
        }
        app.editor.setNumber(field, to: 33)
        #expect(app.undoTitle == "Undo Change \(field.label)")
    }

    @Test func aNewDocumentStartsWithPlainTitles() async {
        let app = await makeApp()
        app.editor.addNote(atScreen: Vector2(30, 40))
        app.undo()
        #expect(app.redoTitle == "Redo Add Note")
        app.newDocument()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo")
    }

    /// Undo and Redo are icons now (toolbar-icons): the step's name is their tooltip and accessibility label
    /// (`ToolbarIconsWindowTests`), not drawn text, so two apps with differently named steps draw the same glyphs.
    @Test func theTopBarDrawsNoTitleTextForTheSteps() async throws {
        func glyphs(_ app: AppModel) -> Int {
            let scene = renderFrame({ ZStack { TopBar(model: app) } }, size: Size(width: Pixels(1400), height: Pixels(100)),
                                    scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
            return scene.glyphs.count
        }
        func edited(named name: String) async throws -> AppModel {
            let app = await makeApp()
            try app.document.perform(.setSticky(StickyNote(frame: CanvasRect(origin: .zero, size: Vector2(160, 100)))), name: name)
            return app
        }
        let long = try await edited(named: "Add Note"), short = try await edited(named: "Move")
        #expect(glyphs(long) == glyphs(short), "the step's name is not drawn in the bar")
        #expect(long.undoTitle == "Undo Add Note" && short.undoTitle == "Undo Move")
        let undone = try await edited(named: "Add Note")
        undone.undo()
        #expect(undone.redoTitle == "Redo Add Note")
    }
}
