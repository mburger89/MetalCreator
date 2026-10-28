import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The DIM-2 kinds drawn (centre, horizontal, vertical and line distances), a dimension's saved label point and the "NX" count.
@MainActor
struct SketchDimensionDrawingKindTests {
    let tilted = Plane(origin: Vector3(5, -2, 7), normal: Vector3(0, -0.6, 0.8), xAxis: .unitX)

    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    func drawn(_ sketch: Sketch, plane: Plane = .xy) -> [OverlayDimension] {
        SketchDimensionDrawing.dimensions(sketch: sketch, solution: SketchSolver.solve(sketch), plane: plane, conflicting: [],
                                          wired: [], units: .millimetres, style: .ansi)
    }

    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length < 1e-9 }

    func world(_ plane: Plane, _ x: Double, _ y: Double) -> Vector3 { plane.xAxis * x + plane.yAxis * y }

    struct Linear {
        var from: Vector3, to: Vector3, direction: Vector3, side: Vector3
        var placement: DimensionPlacement
    }

    func linear(_ dimension: OverlayDimension) throws -> Linear {
        guard case let .linear(from, to, direction, side, placement) = dimension.geometry else {
            throw Failure("not linear: \(dimension.geometry)")
        }
        return Linear(from: from, to: to, direction: direction, side: side, placement: placement)
    }

    /// Two points at (0,0) and (60,40) with one dimension of `kind` between them, its label at `label`.
    func pointPair(_ kind: (SketchEntityID, SketchEntityID) -> DimensionKind, value: Double, label: Vector2? = nil) -> Sketch {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(60, 40))
        let id = sketch.addDimension(kind(a, b), value: value)
        sketch.dimensions[id]?.labelPoint = label
        return sketch
    }

    @Test func horizontalAndVerticalDistancesRunAlongTheAxes() throws {
        for plane in [Plane.xy, tilted] {
            let horizontal = try linear(#require(drawn(pointPair({ .horizontalDistance($0, $1) }, value: 60), plane: plane).first))
            #expect(near(horizontal.from, plane.point(.zero)) && near(horizontal.to, plane.point(Vector2(60, 40))))
            #expect(near(horizontal.direction, plane.xAxis) && near(horizontal.side, plane.yAxis))
            let vertical = try linear(#require(drawn(pointPair({ .verticalDistance($0, $1) }, value: 40), plane: plane).first))
            #expect(near(vertical.direction, plane.yAxis) && near(vertical.side, plane.xAxis))
        }
        let below = pointPair({ .horizontalDistance($0, $1) }, value: 60, label: Vector2(30, -20))
        #expect(try near(linear(#require(drawn(below).first)).side, Vector3(0, -1, 0)), "label below the points")
        let left = pointPair({ .verticalDistance($0, $1) }, value: 40, label: Vector2(-10, 20))
        #expect(try near(linear(#require(drawn(left).first)).side, Vector3(-1, 0, 0)), "label left of the points")
    }

    @Test func aLineDistanceRunsAlongTheFirstNormal() throws {
        var sketch = Sketch()
        let bottom = sketch.addLine(Vector2(0, 0), Vector2(60, 0))
        let top = sketch.addLine(Vector2(0, 40), Vector2(60, 40))
        sketch.addDimension(.lineDistance(bottom, top), value: 40)
        let found = try linear(#require(drawn(sketch).first))
        #expect(near(found.from, Vector3(30, 0, 0)) && near(found.to, Vector3(30, 40, 0)))
        #expect(near(found.direction, Vector3(0, 1, 0)))
        #expect(found.placement == .standoff)
    }

    @Test func centreDistancesJoinCentres() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: .zero, radius: 5)
        let second = sketch.addCircle(center: Vector2(30, 40), radius: 5)
        sketch.addDimension(.centreDistance(first, second), value: 50)
        let found = try linear(#require(drawn(sketch).first))
        #expect(near(found.from, Vector3(0, 0, 0)) && near(found.to, Vector3(30, 40, 0)))
    }

    @Test func aLabelPointPlacesTheLineThroughIt() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(60, 0))
        let length = sketch.addDimension(.length(line), value: 60)
        sketch.dimensions[length]?.labelPoint = Vector2(30, 55)
        let circle = sketch.addCircle(center: .zero, radius: 4)
        let radius = sketch.addDimension(.radius(circle), value: 4)
        sketch.dimensions[radius]?.labelPoint = Vector2(20, 0)
        let found = drawn(sketch)
        try #require(found.count == 2)
        #expect(try linear(found[0]).placement == .through(Vector3(30, 55, 0)))
        guard case let .radial(_, _, _, toward, placement) = found[1].geometry else { throw Failure("not radial") }
        #expect(near(toward, Vector3(1, 0, 0)) && placement == .through(Vector3(20, 0, 0)))
    }

    @Test func equalCirclesReadNX() throws {
        var sketch = Sketch()
        let circles = [Vector2.zero, Vector2(30, 0), Vector2(60, 0)].map { sketch.addCircle(center: $0, radius: 4) }
        let constraints = [sketch.add(.equal(circles[0], circles[1])), sketch.add(.equal(circles[1], circles[2]))]
        sketch.addDimension(.diameter(circles[0]), value: 8)
        #expect(drawn(sketch).map(\.text) == ["3X \u{D8}8"])
        for id in constraints { sketch.constraints[id] = nil }
        #expect(drawn(sketch).map(\.text) == ["\u{D8}8"])
    }

    @Test func coincidentParallelLinesAreLeftOut() {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(60, 0))
        let second = sketch.addLine(Vector2(70, 0), Vector2(90, 0))
        sketch.addDimension(.lineDistance(first, second), value: 0)
        #expect(drawn(sketch).isEmpty)
    }
}
