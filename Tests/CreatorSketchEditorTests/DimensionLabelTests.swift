import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The dimensions' labels in the view (sketcher spec §8): where each kind sits, what it reads, and its colour.
@MainActor
struct DimensionLabelTests {
    func labels(_ sketch: Sketch, plane: Plane = .xy) -> [OverlayLabel] {
        SketchEditorModel(sketch: sketch, plane: plane).overlay.labels
    }

    func near(_ a: Vector3?, _ b: Vector3) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    @Test func aLengthSitsOnTheLinesMiddleAndStandsOffItsNormal() throws {
        let found = labels(RectangleSketch().sketch)
        try #require(found.count == 2)
        #expect(found.map(\.text) == ["60 mm", "40 mm"])
        #expect(near(found[0].position, Vector3(30, 0, 0)) && found[0].nudge == Vector3(0, 1, 0), "above")
        #expect(near(found[1].position, Vector3(60, 20, 0)) && found[1].nudge == Vector3(1, 0, 0), "right of the right edge")
        #expect(found.allSatisfy { $0.tint == .fullyConstrained })
    }

    @Test func aRadiusSitsOnTheArcsMiddleAndADiameterOnTheCirclesUpperRight() throws {
        var sketch = Sketch()
        let centre = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: centre, start: sketch.addPoint(Vector2(10, 0)), end: sketch.addPoint(Vector2(0, 10)))
        sketch.addDimension(.radius(arc), value: 10)
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        sketch.addDimension(.diameter(circle), value: 6)
        let found = labels(sketch)
        try #require(found.count == 2)
        let root = 0.5.squareRoot()
        #expect(found.map(\.text) == ["10 mm", "6 mm"])
        #expect(near(found[0].position, Vector3(10 * root, 10 * root, 0)) && near(found[0].nudge, Vector3(root, root, 0)))
        #expect(near(found[1].position, Vector3(30 + 3 * root, 5 + 3 * root, 0)) && near(found[1].nudge, Vector3(root, root, 0)))
    }

    @Test func aDistanceSitsBetweenItsPointsOrBetweenAPointAndItsFootOnALine() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(30, 40))
        sketch.addDimension(.distance(a, b), value: 50)
        let p = sketch.addPoint(Vector2(105, 10))
        let line = sketch.addLine(Vector2(100, 0), Vector2(110, 0))
        sketch.addDimension(.distance(p, line), value: 10)
        let found = labels(sketch)
        try #require(found.count == 2)
        #expect(found.map(\.text) == ["50 mm", "10 mm"])
        #expect(near(found[0].position, Vector3(15, 20, 0)) && near(found[0].nudge, Vector3(-0.8, 0.6, 0)))
        #expect(near(found[1].position, Vector3(105, 5, 0)), "halfway from the point to its foot on the line")
    }

    @Test func anAngleSitsAtTheCornerAndStandsOffAlongTheBisector() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        let along = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        let up = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(0, 10)))
        sketch.addDimension(.angle(along, up), value: 90)
        let root = 0.5.squareRoot()
        let found = labels(sketch)
        #expect(found.map(\.text) == ["90°"])
        #expect(near(found.first?.position, .zero) && near(found.first?.nudge, Vector3(root, root, 0)))
    }

    @Test func aLabelLiesOnThePlane() {
        let found = labels(RectangleSketch().sketch, plane: .xz)
        #expect(found.allSatisfy { $0.position.y == 0 && $0.nudge?.y == 0 }, "xz: y is the normal")
        #expect(near(found.first?.position, Vector3(30, 0, 0)) && found.first?.nudge == Vector3(0, 0, 1))
    }

    @Test func anExposedDimensionReadsItsNameAndAReferenceItsMeasurementInBrackets() throws {
        var sketch = RectangleSketch().sketch
        let width = try #require(sketch.dimensionIDs.first)
        sketch.renameDimension(width, to: "width")
        sketch.dimensions[width]?.isExposed = true
        let height = try #require(sketch.dimensionIDs.last)
        sketch.dimensions[height]?.isDriving = false
        sketch.dimensions[height]?.value = 1
        let found = labels(sketch)
        #expect(found.map(\.text) == ["width = 60 mm", "(40 mm)"], "the reference reads what it measures, not its stored 1")
        #expect(found.map(\.tint) == [.fullyConstrained, .construction])
    }

    @Test func aDimensionInAConflictIsRed() {
        let rectangle = RectangleSketch()
        var sketch = rectangle.sketch
        sketch.addDimension(.length(rectangle.lines[0]), value: 50)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        guard case .overConstrained = model.solution.status else {
            Issue.record("a 60 and a 50 length on one line must conflict: \(model.solution.status)")
            return
        }
        #expect(model.overlay.labels.contains { $0.tint == .conflicting })
        #expect(model.overlay.labels.count == 3)
    }

    @Test func aDimensionWhoseGeometryIsGoneHasNoLabel() {
        var sketch = RectangleSketch().sketch
        sketch.dimensions[sketch.dimensionIDs[0]]?.kind = .length(SketchEntityID(999))
        #expect(labels(sketch).map(\.text) == ["40 mm"])
    }

    @Test func theDimensionToolAddsALabel() {
        let model = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
        #expect(model.overlay.labels.isEmpty)
        model.choose(.dimension)
        model.click(at: Vector2(30, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        #expect(model.overlay.labels.map(\.text) == ["60 mm"])
    }
}
