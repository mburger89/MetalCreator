import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorDrawingEditor

/// New and Open… commit what is typed in either inspector before they ask about unsaved changes.
@MainActor
struct NewOpenPendingEntryTests {
    func typedGraphValue() async -> (AppModel, NodeID) {
        var builder = GraphBuilder()
        let id = builder.solid(distance: 10).extrude.id
        let app = await makeApp(builder.graph)
        app.editor.notePendingEntry(PendingEntry(text: "25") { value in
            try? app.document.perform(.setInput(id, "distance", .number(value)))
        })
        return (app, id)
    }

    func typedDrawingValue() async -> AppModel {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        app.drawing.editor.notePendingDraft(owner: UUID()) { app.drawing.editor.setTitleField(.tolerance, to: "typed") }
        return app
    }

    @Test func newAsksAboutATypedGraphValueAndKeepsIt() async throws {
        let (app, id) = await typedGraphValue()
        app.newDocument()
        #expect(app.alert == .discardChanges)
        #expect(app.document.graph.nodes[id]?.inputValues["distance"] == .number(25))
    }

    @Test func openAsksAboutATypedGraphValueAndKeepsIt() async throws {
        let (app, id) = await typedGraphValue()
        await app.openDocument(using: ScriptedPicker([]))
        #expect(app.alert == .discardChanges)
        #expect(app.document.graph.nodes[id]?.inputValues["distance"] == .number(25))
    }

    @Test func newAsksAboutATypedDrawingValueAndKeepsIt() async throws {
        let app = await typedDrawingValue()
        app.newDocument()
        #expect(app.alert == .discardChanges)
        #expect(app.document.drawings.settings.generalTolerance == "typed")
    }

    @Test func openAsksAboutATypedDrawingValueAndKeepsIt() async throws {
        let app = await typedDrawingValue()
        await app.openDocument(using: ScriptedPicker([]))
        #expect(app.alert == .discardChanges)
        #expect(app.document.drawings.settings.generalTolerance == "typed")
    }
}
