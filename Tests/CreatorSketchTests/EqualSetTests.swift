import CreatorGeometry
import Testing
@testable import CreatorSketch

struct EqualSetTests {
    @Test func equalCirclesFormOneSetTransitively() {
        var sketch = Sketch()
        let a = sketch.addCircle(center: .zero, radius: 1)
        let b = sketch.addCircle(center: Vector2(5, 0), radius: 2)
        let c = sketch.addCircle(center: Vector2(10, 0), radius: 3)
        let d = sketch.addCircle(center: Vector2(15, 0), radius: 4)
        sketch.add(.equal(a, b))
        sketch.add(.equal(c, b))
        #expect(sketch.equalSet(of: c) == [a, b, c])
        #expect(sketch.equalSet(of: a) == [a, b, c])
        #expect(sketch.equalSet(of: d) == [d])
    }

    @Test func arcsAndCirclesAreSetsOfTheirOwnKind() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 1)
        let centre = sketch.addPoint(Vector2(5, 0))
        let start = sketch.addPoint(Vector2(6, 0))
        let end = sketch.addPoint(Vector2(5, 1))
        let arc = sketch.addArc(center: centre, start: start, end: end)
        sketch.add(.equal(circle, arc))
        #expect(sketch.equalSet(of: circle) == [circle])
        #expect(sketch.equalSet(of: arc) == [arc])
    }

    @Test func aLineHasNoEqualSet() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(3, 0))
        #expect(sketch.equalSet(of: line).isEmpty)
    }
}
