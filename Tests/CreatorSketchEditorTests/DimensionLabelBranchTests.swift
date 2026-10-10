import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The branches of the dimension labels (sketcher spec §8) that `DimensionLabelTests` leaves out: a suspended
/// projection, parallel angle lines, coincident points (the `up` fallback) and a dimension whose entities don't fit
/// its kind. A label that can't be placed is left out; it never reaches the screen at a made-up spot.
@MainActor
struct DimensionLabelBranchTests {
    func labels(_ sketch: Sketch) -> [OverlayLabel] {
        SketchEditorModel(sketch: sketch, plane: .xy).overlay.labels
    }

    func near(_ a: Vector3?, _ b: Vector3) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    /// A projected line from (0, 0) to (30, 0), suspended or not, with a point at (10, 10).
    func projected(suspended: Bool) -> (sketch: Sketch, line: SketchEntityID, point: SketchEntityID) {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "edge1", curve: .line(Vector2(0, 0), Vector2(30, 0)), isSuspended: suspended)
        let line = sketch.add(SketchEntity(.projected(source)))
        let point = sketch.addPoint(Vector2(10, 10))
        return (sketch, line, point)
    }

    @Test func aDistanceToAProjectedLineIsLabelledUnlessTheProjectionIsSuspended() throws {
        var live = projected(suspended: false)
        live.sketch.addDimension(.distance(live.point, live.line), value: 10)
        #expect(labels(live.sketch).map(\.text) == ["10 mm"])
        var suspended = projected(suspended: true)
        suspended.sketch.addDimension(.distance(suspended.point, suspended.line), value: 10)
        #expect(labels(suspended.sketch).isEmpty, "a suspended projection has no geometry to anchor the label on")
    }

    @Test func twoParallelLinesAnchorTheAngleAtTheirCentreAndStandOffUp() throws {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let second = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        sketch.addDimension(.angle(first, second), value: 0)
        let found = try #require(labels(sketch).first)
        #expect(near(found.position, Vector3(5, 5, 0)), "no corner: the middle of the four ends")
        #expect(found.nudge == Vector3(0, 1, 0), "the two middles are opposite each other, so the bisector is nothing: up")
    }

    @Test func coincidentPointsStandTheirDistanceLabelOffUp() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(4, 4))
        let b = sketch.addPoint(Vector2(4, 4))
        sketch.addDimension(.distance(a, b), value: 0)
        let found = try #require(labels(sketch).first)
        #expect(near(found.position, Vector3(4, 4, 0)))
        #expect(found.nudge == Vector3(0, 1, 0), "no direction between them: up")
    }

    @Test func aDegenerateLineStandsItsLengthLabelOffUp() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(2, 2), Vector2(2, 2))
        sketch.addDimension(.length(line), value: 0)
        #expect(try #require(labels(sketch).first).nudge == Vector3(0, 1, 0))
    }

    @Test func aDimensionWhoseEntitiesDontFitItsKindHasNoLabel() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let other = sketch.addPoint(Vector2(5, 0))
        let line = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        let kinds: [DimensionKind] = [
            .length(point),         // a length needs a line
            .radius(line),          // a radius needs an arc or a circle
            .diameter(point),
            .distance(line, circle),   // a distance takes points, or a point and a line
            .distance(circle, point),
            .angle(point, other),   // an angle takes two lines
            .angle(line, point),
        ]
        for kind in kinds { sketch.addDimension(kind, value: 1) }
        #expect(labels(sketch).isEmpty)
    }

    /// Labels are neither capped nor culled by count here (the viewport drops those off screen): every dimension that
    /// can be placed has one.
    @Test func everyPlaceableDimensionHasALabel() {
        var sketch = Sketch()
        for index in 0..<40 {
            let line = sketch.addLine(Vector2(Double(index), 0), Vector2(Double(index), 5))
            sketch.addDimension(.length(line), value: 5)
        }
        #expect(labels(sketch).count == 40)
    }
}
