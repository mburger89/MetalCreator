import CreatorGeometry
@testable import CreatorSketch
import Foundation
import Testing

/// A sketch's dimensions as world geometry on its plane (DIM-3 Task 9).
struct SketchDimensionGeometryTests {
    /// Tilted about X, so a plane axis is not a world axis: x = (1,0,0), y = (0,0.8,0.6), normal = (0,-0.6,0.8).
    let tilted = Plane(origin: Vector3(1, 2, 3), normal: Vector3(0, -0.6, 0.8), xAxis: .unitX)

    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-6 }

    func geometry(_ id: DimensionID, _ sketch: Sketch) -> DimensionGeometry? {
        SketchDimensionGeometry.geometry(of: id, in: sketch, solution: SketchSolver.solve(sketch), plane: tilted)
    }

    @Test func eachKindMapsOntoATiltedPlane() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(30, 0))
        let c = sketch.addPoint(Vector2(10, 20))
        let base = sketch.addLine(from: a, to: b)
        let rise = sketch.addLine(Vector2(0, 0), Vector2(0, 10))
        let hole = sketch.addCircle(center: Vector2(50, 50), radius: 5)
        let length = sketch.addDimension(.length(base), value: 30)
        let between = sketch.addDimension(.distance(a, c), value: 22.360679774997898)
        let toLine = sketch.addDimension(.distance(c, base), value: 20)
        let radius = sketch.addDimension(.radius(hole), value: 5)
        let diameter = sketch.addDimension(.diameter(hole), value: 10)
        let angle = sketch.addDimension(.angle(base, rise), value: 90)
        let solution = SketchSolver.solve(sketch)
        let at = { (id: SketchEntityID) in tilted.point(solution.points[id] ?? Vector2(.nan, .nan)) }

        guard case let .linear(from, to, direction, _, _)? = geometry(length, sketch) else { Issue.record("length"); return }
        #expect(near(from, at(a)) && near(to, at(b)) && near(direction, tilted.xAxis))

        guard case let .linear(pFrom, pTo, _, _, _)? = geometry(between, sketch) else { Issue.record("distance"); return }
        #expect(near(pFrom, at(a)) && near(pTo, at(c)))

        // c (10, 20) to its foot (10, 0) on the infinite base line.
        guard case let .linear(lFrom, lTo, lDirection, _, _)? = geometry(toLine, sketch) else { Issue.record("point-line"); return }
        #expect(near(lFrom, tilted.point(Vector2(10, 20))) && near(lTo, tilted.point(Vector2(10, 0))))
        #expect(near(lDirection, tilted.yAxis * -1))

        for id in [radius, diameter] {
            guard case let .radial(center, r, normal, toward, _)? = geometry(id, sketch) else { Issue.record("radial"); return }
            #expect(near(center, tilted.point(Vector2(50, 50))) && abs(r - 5) < 1e-6 && near(normal, tilted.normal))
            #expect(near(toward, (tilted.xAxis + tilted.yAxis) * (1 / 2.0.squareRoot())))
        }

        guard case let .angular(vertex, first, second, normal, _)? = geometry(angle, sketch) else { Issue.record("angle"); return }
        #expect(near(vertex, tilted.point(.zero)) && near(first, tilted.point(Vector2(15, 0))))
        #expect(near(second, tilted.point(Vector2(0, 5))) && near(normal, tilted.normal))
    }

    @Test func anArcsRadiusLeadsOutAtItsMiddle() throws {
        var sketch = Sketch()
        let centre = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        let arc = sketch.addArc(center: centre, start: start, end: end)
        let radius = sketch.addDimension(.radius(arc), value: 10)
        guard case let .radial(center, r, _, toward, _)? = geometry(radius, sketch) else { Issue.record("radial"); return }
        #expect(near(center, tilted.point(.zero)) && abs(r - 10) < 1e-6)
        #expect(near(toward, (tilted.xAxis + tilted.yAxis) * (1 / 2.0.squareRoot())))
    }

    @Test func aPointOnItsLineHasNoDistance() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(30, 0))
        let point = sketch.addPoint(Vector2(12, 0))
        let id = sketch.addDimension(.distance(point, line), value: 0, isDriving: false)
        #expect(geometry(id, sketch) == nil)
    }

    @Test func aSuspendedProjectionHasNoDimension() {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .circle(center: .zero, radius: 5), isSuspended: true)
        let circle = sketch.add(SketchEntity(.projected(source)))
        let id = sketch.addDimension(.radius(circle), value: 5, isDriving: false)
        #expect(geometry(id, sketch) == nil)
    }

    @Test func aLiveProjectionIsDimensioned() {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .line(Vector2(0, 0), Vector2(0, 8)))
        let line = sketch.add(SketchEntity(.projected(source)))
        let id = sketch.addDimension(.length(line), value: 8, isDriving: false)
        guard case let .linear(from, to, _, _, _)? = geometry(id, sketch) else { Issue.record("length"); return }
        #expect(near(from, tilted.point(.zero)) && near(to, tilted.point(Vector2(0, 8))))
    }

    @Test func aMissingDimensionHasNoGeometry() {
        #expect(geometry(DimensionID(99), Sketch()) == nil)
    }
}
