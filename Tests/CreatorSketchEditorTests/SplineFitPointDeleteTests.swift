import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// A plain click on a fit point of a selected spline selects the point instead of the curve, so Delete removes only the
/// point (ui-polish finding 1); the spline's fit points and knobs stay shown through the selected point.
@MainActor
struct SplineFitPointDeleteTests {
    /// A spline through three points, and a separate line far from it.
    struct Fixture {
        let model: SketchEditorModel
        let host: RecordingHost
        let spline: SketchEntityID
        let middle: SketchEntityID
        let line: SketchEntityID
    }

    func fixture() -> Fixture {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(15, 12), Vector2(30, 0)])
        let line = sketch.addLine(Vector2(0, -40), Vector2(30, -40))
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.select)
        let middle = sketch.splineParts(of: spline)!.points[1]
        return Fixture(model: model, host: RecordingHost(model), spline: spline, middle: middle, line: line)
    }

    /// A place on the drawn curve between its fit points.
    func curvePoint(_ model: SketchEditorModel, _ spline: SketchEntityID) throws -> Vector2 {
        let polyline = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution)).curve().polyline()
        return polyline[polyline.count / 4]
    }

    func splineCount(_ model: SketchEditorModel) -> Int {
        model.sketch.entityIDs.filter { model.sketch.splineParts(of: $0) != nil }.count
    }

    @Test func aPlainClickOnAFitPointOfTheSelectedSplineLeavesOnlyThePointSelected() throws {
        let f = fixture()
        f.model.click(at: try curvePoint(f.model, f.spline), tolerance: 0.5, modifiers: [])
        #expect(f.model.selection == [f.spline])
        f.model.click(at: Vector2(15, 12), tolerance: 0.5, modifiers: [])
        #expect(f.model.selection == [f.middle])
        #expect(f.model.handleSplines == [f.spline], "the fit points and knobs are still shown")
    }

    @Test func deleteThenRemovesOnlyThatPoint() throws {
        let f = fixture()
        f.model.click(at: try curvePoint(f.model, f.spline), tolerance: 0.5, modifiers: [])
        f.model.click(at: Vector2(15, 12), tolerance: 0.5, modifiers: [])
        f.model.deleteSelection()
        #expect(f.host.commits.map(\.name) == ["Delete"])
        #expect(splineCount(f.model) == 1, "the spline stays while two points remain")
        #expect(f.model.sketch.splineParts(of: f.spline)?.points.count == 2)
    }

    @Test func aClickOnTheCurveAwayFromItsPointsThenDeleteRemovesTheCurve() throws {
        let f = fixture()
        f.model.click(at: try curvePoint(f.model, f.spline), tolerance: 0.5, modifiers: [])
        f.model.deleteSelection()
        #expect(splineCount(f.model) == 0)
    }

    @Test func shiftClickStillAddsThePointToTheSelectedSpline() throws {
        let f = fixture()
        f.model.click(at: try curvePoint(f.model, f.spline), tolerance: 0.5, modifiers: [])
        f.model.click(at: Vector2(15, 12), tolerance: 0.5, modifiers: [.shift])
        #expect(f.model.selection == [f.spline, f.middle])
        f.model.deleteSelection()
        #expect(splineCount(f.model) == 0, "both were selected on purpose")
    }

    @Test func aPointOfOneSplineAndASeparateEntityBothDelete() throws {
        let f = fixture()
        f.model.click(at: Vector2(15, 12), tolerance: 0.5, modifiers: [])
        f.model.click(at: Vector2(15, -40), tolerance: 0.5, modifiers: [])
        #expect(f.model.selection == [f.middle, f.line])
        f.model.deleteSelection()
        #expect(f.model.sketch.entities[f.line] == nil)
        #expect(f.model.sketch.splineParts(of: f.spline)?.points.count == 2)
    }
}
