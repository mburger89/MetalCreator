import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// The open sketch's dimensions are handed to the viewport as ANSI dimensions (DIM-1) and go when the sketch does.
@MainActor
struct SketchDimensionsShownTests {
    func openSketch() async -> AppModel {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        return app
    }

    @Test func theOpenSketchsDimensionsAreShownAndGoWithIt() async {
        let app = await openSketch()
        #expect(app.viewport.dimensions.count == 2)
        #expect(app.viewport.dimensions.map(\.id.rawValue).allSatisfy { $0.hasPrefix("sketch/") })
        #expect(app.shownDimensions() == app.viewport.dimensions)
        app.finishSketch()
        #expect(app.viewport.dimensions.isEmpty)
        #expect(app.shownDimensions().isEmpty)
    }

    @Test func aNewDimensionIsShownAfterTheEditorChanges() async throws {
        let app = await openSketch()
        let session = try #require(app.sketch)
        session.editor.choose(.dimension)
        session.editor.click(at: Vector2(30, 40.2), tolerance: 1, modifiers: [])
        session.editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        await session.settle()
        #expect(app.viewport.dimensions.count == 3)
    }

    @Test func theTextFollowsTheDocumentsUnits() async throws {
        let app = await openSketch()
        #expect(app.viewport.dimensions.map(\.text) == ["60", "40"])
        try app.document.perform(.setUnits(DocumentUnits(length: .inches)), name: UndoName.changeUnits)
        app.refreshSketch()
        await app.sketch?.settle()
        #expect(app.viewport.dimensions.map(\.text) == ["2.36", "1.57"])
    }
}
