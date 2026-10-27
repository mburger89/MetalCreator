import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// A sketch's dimensions drawn as ANSI dimensions (DIM-1, spec §3 and §5): where each kind's geometry lies on the plane, what
/// its text reads, its tint, and when it is left out.
@MainActor
struct SketchDimensionDrawingTests {
    /// A plane tilted about its x axis and moved off the origin, so that a mix-up of axes shows.
    let tilted = Plane(origin: Vector3(5, -2, 7), normal: Vector3(0, -0.6, 0.8), xAxis: .unitX)

    func drawn(_ sketch: Sketch, plane: Plane = .xy, conflicting: Set<DimensionID> = [], wired: Set<DimensionID> = [],
               units: DocumentUnits = .millimetres) -> [OverlayDimension] {
        SketchDimensionDrawing.dimensions(sketch: sketch, solution: SketchSolver.solve(sketch), plane: plane,
                                          conflicting: conflicting, wired: wired, units: units, style: .ansi)
    }

    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length < 1e-9 }

    /// A world vector from a plane one.
    func world(_ plane: Plane, _ x: Double, _ y: Double) -> Vector3 { plane.xAxis * x + plane.yAxis * y }

    /// One dimension of each kind, every value equal to what its geometry measures so that the solve moves nothing.
    func everyKind() -> Sketch {
        var sketch = Sketch()
        let lengthLine = sketch.addLine(Vector2(0, -50), Vector2(60, -50))
        sketch.addDimension(.length(lengthLine), value: 60)
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(30, 40))
        sketch.addDimension(.distance(a, b), value: 50)
        let p = sketch.addPoint(Vector2(105, 10))
        let line = sketch.addLine(Vector2(100, 0), Vector2(110, 0))
        sketch.addDimension(.distance(p, line), value: 10)
        let centre = sketch.addPoint(Vector2(0, 100))
        let arc = sketch.addArc(center: centre, start: sketch.addPoint(Vector2(10, 100)), end: sketch.addPoint(Vector2(0, 110)))
        sketch.addDimension(.radius(arc), value: 10)
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        sketch.addDimension(.diameter(circle), value: 6)
        let corner = sketch.addPoint(Vector2(200, 0))
        let along = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(210, 0)))
        let up = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(200, 10)))
        sketch.addDimension(.angle(along, up), value: 90)
        return sketch
    }

    @Test func eachKindDrawsItsGeometryOnThePlane() throws {
        let plane = tilted
        let found = drawn(everyKind(), plane: plane)
        try #require(found.count == 6)
        let root = 0.5.squareRoot()
        func linear(_ index: Int) throws -> (from: Vector3, to: Vector3, direction: Vector3, side: Vector3) {
            guard case let .linear(from, to, direction, side, placement) = found[index].geometry, placement == .standoff else {
                throw Failure("dimension \(index) is not a standoff linear: \(found[index].geometry)")
            }
            return (from, to, direction, side)
        }
        let length = try linear(0)
        #expect(near(length.from, plane.point(Vector2(0, -50))) && near(length.to, plane.point(Vector2(60, -50))))
        #expect(near(length.direction, world(plane, 1, 0)) && near(length.side, world(plane, 0, 1)), "measured along x, drawn above")
        let distance = try linear(1)
        #expect(near(distance.from, plane.point(.zero)) && near(distance.to, plane.point(Vector2(30, 40))))
        #expect(near(distance.direction, world(plane, 0.6, 0.8)) && near(distance.side, world(plane, -0.8, 0.6)))
        let toLine = try linear(2)
        #expect(near(toLine.from, plane.point(Vector2(105, 10))) && near(toLine.to, plane.point(Vector2(105, 0))), "to the foot")
        #expect(near(toLine.direction, world(plane, 0, -1)) && near(toLine.side, world(plane, 1, 0)))
        guard case let .radial(center, radius, normal, toward, radialPlacement) = found[3].geometry else {
            throw Failure("the radius is not radial: \(found[3].geometry)")
        }
        #expect(near(center, plane.point(Vector2(0, 100))) && radius == 10 && near(normal, plane.normal) && radialPlacement == .standoff)
        #expect(near(toward, world(plane, root, root)), "the arc's middle")
        guard case let .radial(circleCentre, circleRadius, _, circleToward, _) = found[4].geometry else {
            throw Failure("the diameter is not radial: \(found[4].geometry)")
        }
        #expect(near(circleCentre, plane.point(Vector2(30, 5))) && circleRadius == 3)
        #expect(near(circleToward, world(plane, root, root)), "a circle: 45 degrees")
        guard case let .angular(vertex, first, second, angularNormal, angularPlacement) = found[5].geometry else {
            throw Failure("the angle is not angular: \(found[5].geometry)")
        }
        #expect(near(vertex, plane.point(Vector2(200, 0))) && near(first, plane.point(Vector2(205, 0))))
        #expect(near(second, plane.point(Vector2(200, 5))) && near(angularNormal, plane.normal) && angularPlacement == .standoff)
    }

    @Test func textsFollowTheStyleAndTheUnits() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(60, 0))
        let length = sketch.addDimension(.length(line), value: 60)
        let arc = sketch.addArc(center: sketch.addPoint(Vector2(0, 50)), start: sketch.addPoint(Vector2(10, 50)),
                                end: sketch.addPoint(Vector2(0, 60)))
        sketch.addDimension(.radius(arc), value: 10)
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 10)
        sketch.addDimension(.diameter(circle), value: 20)
        let corner = sketch.addPoint(Vector2(100, 0))
        let along = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(110, 0)))
        let slant = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(110, 10)))
        sketch.addDimension(.angle(along, slant), value: 45)
        #expect(drawn(sketch).map(\.text) == ["60", "R10", "\u{D8}20", "45°"])
        #expect(drawn(sketch, units: DocumentUnits(length: .inches)).map(\.text) == ["2.36", "R.39", "\u{D8}.79", "45°"])
        // Exposed: named. Reference: in brackets, reading what it measures (the stored 1 is not shown).
        sketch.renameDimension(length, to: "width")
        sketch.dimensions[length]?.isExposed = true
        #expect(drawn(sketch).first?.text == "width = 60")
        sketch.dimensions[length]?.isExposed = false
        sketch.dimensions[length]?.isDriving = false
        sketch.dimensions[length]?.value = 1
        #expect(drawn(sketch).first?.text == "(60)")
    }

    @Test func tintsSayDrivingReferenceOrConflict() throws {
        let rectangle = RectangleSketch()
        var sketch = rectangle.sketch
        #expect(drawn(sketch).map(\.tint) == [.dimensionDriving, .dimensionDriving])
        #expect(drawn(sketch, conflicting: [rectangle.width]).map(\.tint) == [.conflicting, .dimensionDriving])
        #expect(drawn(sketch, wired: [rectangle.height]).map(\.tint) == [.dimensionDriving, .dimensionReference], "wired")
        #expect(drawn(sketch, wired: [rectangle.height]).map(\.text) == ["60", "(40)"], "a wired value is shown in brackets")
        sketch.dimensions[rectangle.height]?.isDriving = false
        #expect(drawn(sketch).map(\.tint) == [.dimensionDriving, .dimensionReference], "reference")
        #expect(drawn(sketch, conflicting: [rectangle.height]).map(\.tint) == [.dimensionDriving, .conflicting],
                "a conflict wins over a reference")
    }

    @Test func aDimensionInARealConflictIsRed() {
        let rectangle = RectangleSketch()
        var sketch = rectangle.sketch
        sketch.addDimension(.length(rectangle.lines[0]), value: 50)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        guard case .overConstrained = model.solution.status else {
            Issue.record("a 60 and a 50 length on one line must conflict: \(model.solution.status)")
            return
        }
        #expect(model.dimensions.contains { $0.tint == .conflicting })
        #expect(model.dimensions.count == 3)
    }

    @Test func aDimensionWhoseGeometryIsGoneIsLeftOut() {
        // A suspended projected edge has no geometry to dimension; a live one has.
        for suspended in [false, true] {
            var sketch = Sketch()
            let source = ProjectionSource(reference: "edge1", curve: .line(Vector2(0, 0), Vector2(30, 0)), isSuspended: suspended)
            let line = sketch.add(SketchEntity(.projected(source)))
            let point = sketch.addPoint(Vector2(10, 10))
            sketch.addDimension(.distance(point, line), value: 10)
            #expect(drawn(sketch).map(\.text) == (suspended ? [] : ["10"]), "suspended: \(suspended)")
        }
        // A point on its line is at distance 0 from it: nothing to draw between them.
        var onLine = Sketch()
        let line = onLine.addLine(Vector2(0, 0), Vector2(30, 0))
        onLine.addDimension(.distance(onLine.addPoint(Vector2(10, 0)), line), value: 0)
        #expect(drawn(onLine).isEmpty, "a point–line distance with the point on the line")
        // Coincident points, a line with no length, a missing entity.
        var degenerate = Sketch()
        degenerate.addDimension(.distance(degenerate.addPoint(Vector2(4, 4)), degenerate.addPoint(Vector2(4, 4))), value: 0)
        degenerate.addDimension(.length(degenerate.addLine(Vector2(2, 2), Vector2(2, 2))), value: 0)
        degenerate.addDimension(.length(SketchEntityID(999)), value: 5)
        #expect(drawn(degenerate).isEmpty)
        // A zero radius has no circle to dimension.
        var flat = Sketch()
        flat.addDimension(.diameter(flat.addCircle(center: .zero, radius: 0)), value: 0)
        #expect(drawn(flat).isEmpty)
    }

    @Test func aDimensionWhoseEntitiesDontFitItsKindIsLeftOut() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let other = sketch.addPoint(Vector2(5, 0))
        let line = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        let kinds: [DimensionKind] = [
            .length(point),            // a length needs a line
            .radius(line),             // a radius needs an arc or a circle
            .diameter(point),
            .distance(line, circle),   // a distance takes points, or a point and a line
            .distance(circle, point),
            .angle(point, other),      // an angle takes two lines
            .angle(line, point),
        ]
        for kind in kinds { sketch.addDimension(kind, value: 1) }
        #expect(drawn(sketch).isEmpty)
    }

    @Test func twoParallelLinesAnchorTheAngleAtTheirCentre() throws {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let second = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        sketch.addDimension(.angle(first, second), value: 0)
        let found = try #require(drawn(sketch).first)
        guard case let .angular(vertex, _, _, _, _) = found.geometry else {
            Issue.record("not angular: \(found.geometry)")
            return
        }
        #expect(near(vertex, Vector3(5, 5, 0)), "no corner: the middle of the four ends")
    }

    @Test func everyPlaceableDimensionIsDrawn() {
        var sketch = Sketch()
        for index in 0..<40 {
            let line = sketch.addLine(Vector2(Double(index), 0), Vector2(Double(index), 5))
            sketch.addDimension(.length(line), value: 5)
        }
        #expect(drawn(sketch).count == 40)
    }

    @Test func idsAreSketchPrefixed() {
        let id = SketchDimensionDrawing.overlayID(DimensionID(3))
        #expect(id.rawValue == "sketch/3")
        #expect(SketchDimensionDrawing.dimensionID(from: id) == DimensionID(3))
        #expect(SketchDimensionDrawing.dimensionID(from: OverlayDimensionID("feature/x")) == nil)
        #expect(SketchDimensionDrawing.dimensionID(from: OverlayDimensionID("sketch/x")) == nil)
        let rectangle = RectangleSketch()
        let expected = [rectangle.width, rectangle.height].map(SketchDimensionDrawing.overlayID)
        #expect(drawn(rectangle.sketch).map(\.id) == expected)
    }

    @Test func theEditorDrawsInItsUnitsAndThePlane() {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xz)
        #expect(model.dimensions.map(\.text) == ["60", "40"])
        model.units = DocumentUnits(length: .inches)
        #expect(model.dimensions.map(\.text) == ["2.36", "1.57"])
        if case let .linear(from, _, _, _, _)? = model.dimensions.first?.geometry {
            #expect(near(from, .zero))
        } else {
            Issue.record("the width is not linear")
        }
    }

    @Test func theDimensionToolAddsADimension() {
        let model = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
        #expect(model.dimensions.isEmpty)
        model.choose(.dimension)
        model.click(at: Vector2(30, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        #expect(model.dimensions.map(\.text) == ["60"])
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
