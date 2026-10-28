import CreatorGeometry
import CreatorGraph
import CreatorSketch
import Testing
@testable import CreatorApp

/// A flipping sketch value typed on the part (DIM-3 Task 13, merge task M): `FeatureValueBoxTests`, continued.
extension FeatureValueBoxTests {
    @Test func aFlippingSketchValueIsRefusedOnThePart() async throws {
        var builder = GraphBuilder()
        var sketch = Sketch(plane: .fixed(.xy))
        let corners = [Vector2(0, 0), Vector2(60, 0), Vector2(30, 52)].map { sketch.addPoint($0) }
        let lines = (0..<3).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 3]) }
        sketch.add(.horizontal(lines[0]))
        sketch.add(.fix(corners[0], at: .zero))
        sketch.addDimension(.length(lines[0]), value: 60)
        let side = sketch.addDimension(.length(lines[1]), value: 60)
        sketch.addDimension(.length(lines[2]), value: 60)
        let box = builder.sketchedBox(sketch)
        let app = await makeApp(builder.graph)
        await select(app, box.sketch)
        let dimension = FeatureDimension.overlayID(node: box.sketch.id, target: .sketchDimension(side))
        let before = app.document.content
        // Shortening one side to 0.5 solves, but swings the apex through the base: the triangle turns over.
        #expect(await app.dimensionRouter.commitValue("0.5", to: dimension) == .refused("This value would flip the sketch."))
        #expect(app.document.content == before)
        #expect(!app.document.canUndo && !app.document.isHoldingResults)
    }
}
