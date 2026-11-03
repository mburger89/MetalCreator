import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The Spline tool's rubber band is the curve the commit makes, inferred Tangent included.
@MainActor
struct SplineBandTests {
    func makeModel(_ sketch: Sketch) -> SketchEditorModel {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.spline)
        _ = RecordingHost(model)
        return model
    }

    func click(_ model: SketchEditorModel, _ x: Double, _ y: Double, _ modifiers: ViewportModifiers = []) {
        model.click(at: Vector2(x, y), tolerance: 1, modifiers: modifiers)
    }

    /// The band's curve as drawn.
    func bandPolyline(_ model: SketchEditorModel) throws -> [Vector2] {
        let curve = try #require(model.preview.curves.first)
        return SketchOverlayBuilder.polyline(of: curve)
    }

    /// The committed spline as drawn.
    func committedPolyline(_ model: SketchEditorModel) throws -> [Vector2] {
        let spline = try #require(model.sketch.entityIDs.first { model.sketch.splineParts(of: $0) != nil })
        return try #require(model.sketch.splineDefinition(of: spline, solution: model.solution)).curve().polyline()
    }

    func expectSame(_ a: [Vector2], _ b: [Vector2], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count && a.count > 2, sourceLocation: sourceLocation)
        for (p, q) in zip(a, b) { #expect((p - q).length < 1e-6, sourceLocation: sourceLocation) }
    }

    func lineSketch() -> Sketch {
        var sketch = Sketch()
        sketch.addLine(Vector2(-20, 0), Vector2(0, 0))
        return sketch
    }

    func arcSketch() -> Sketch {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let from = sketch.addPoint(Vector2(10, 0))
        let to = sketch.addPoint(Vector2(0, 10))
        sketch.addArc(center: center, start: from, end: to)
        return sketch
    }

    @Test func startOnALineEnd() throws {
        let model = makeModel(lineSketch())
        click(model, 0, 0)
        click(model, 10, 8)
        model.hover(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        let band = try bandPolyline(model)
        click(model, 20, 0)
        model.finish()
        let committed = try committedPolyline(model)
        expectSame(band, committed)
        let plain = SketchOverlayBuilder.splinePolyline(through: [Vector2(0, 0), Vector2(10, 8), Vector2(20, 0)])
        #expect(zip(band, plain).contains { ($0 - $1).length > 1e-3 }, "the tangent bends the band")
    }

    @Test func startOnAnArcEnd() throws {
        let model = makeModel(arcSketch())
        click(model, 0, 10)
        click(model, -10, 14)
        model.hover(at: Vector2(-20, 10), tolerance: 1, modifiers: [])
        let band = try bandPolyline(model)
        click(model, -20, 10)
        model.finish()
        expectSame(band, try committedPolyline(model))
    }

    @Test func landingOnALineEnd() throws {
        let model = makeModel(lineSketch())
        click(model, 20, 0)
        click(model, 10, 8)
        model.hover(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        let band = try bandPolyline(model)
        click(model, 0, 0)
        model.finish()
        expectSame(band, try committedPolyline(model))
        let plain = SketchOverlayBuilder.splinePolyline(through: [Vector2(20, 0), Vector2(10, 8), Vector2(0, 0)])
        #expect(zip(band, plain).contains { ($0 - $1).length > 1e-3 })
    }

    @Test func commandSuppressesTheTangentAtTheStart() throws {
        let model = makeModel(lineSketch())
        click(model, 0, 0, [.command])
        click(model, 10, 8)
        model.hover(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        let band = try bandPolyline(model)
        click(model, 20, 0)
        model.finish()
        expectSame(band, try committedPolyline(model))
    }

    @Test func commandSuppressesTheTangentAtTheLanding() throws {
        let model = makeModel(lineSketch())
        click(model, 20, 0)
        click(model, 10, 8)
        model.hover(at: Vector2(0, 0), tolerance: 1, modifiers: [.command])
        let band = try bandPolyline(model)
        click(model, 0, 0, [.command])
        click(model, 0, 0, [.command])
        expectSame(band, try committedPolyline(model))
    }

    @Test func noInferenceIsUnchanged() throws {
        let model = makeModel(Sketch())
        click(model, 0, 0)
        click(model, 10, 8)
        model.hover(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        let curve = try #require(model.preview.curves.first)
        #expect(curve == .spline(through: [Vector2(0, 0), Vector2(10, 8), Vector2(20, 0)]))
        let band = try bandPolyline(model)
        click(model, 20, 0)
        model.finish()
        expectSame(band, try committedPolyline(model))
    }
}
