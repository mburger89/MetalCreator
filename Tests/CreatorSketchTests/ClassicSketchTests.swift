import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// The spec §10 classic sketches, each fully constrained.
struct ClassicSketchTests {
    @Test func rectangleSolvesToZeroDegreesOfFreedom() throws {
        let rectangle = ConstrainedRectangle()
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .solved)
        let expected = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)]
        for (i, corner) in expected.enumerated() {
            #expect(isClose(try #require(rectangle.corner(i, in: solution)), corner))
        }
        #expect(solution.freedom.values.allSatisfy { $0 == .fixed })
    }

    /// A slot: two lines joined by two tangent semicircles of equal radius.
    struct Slot {
        var sketch = Sketch()
        let top: SketchEntityID
        let left: SketchEntityID
        let right: SketchEntityID
        let leftCenter: SketchEntityID
        let rightCenter: SketchEntityID
        let length: DimensionID

        init(length value: Double = 40, radius: Double = 5) {
            leftCenter = sketch.addPoint(Vector2(0.3, 0.2))
            rightCenter = sketch.addPoint(Vector2(value - 0.4, -0.3))
            let topLeft = sketch.addPoint(Vector2(0.2, radius + 0.3))
            let topRight = sketch.addPoint(Vector2(value + 0.3, radius - 0.2))
            let bottomRight = sketch.addPoint(Vector2(value - 0.2, -radius + 0.4))
            let bottomLeft = sketch.addPoint(Vector2(-0.3, -radius - 0.1))
            top = sketch.addLine(from: topRight, to: topLeft)
            let bottom = sketch.addLine(from: bottomLeft, to: bottomRight)
            left = sketch.addArc(center: leftCenter, start: topLeft, end: bottomLeft)
            right = sketch.addArc(center: rightCenter, start: bottomRight, end: topRight)
            for (line, arc) in [(top, left), (top, right), (bottom, left), (bottom, right)] {
                sketch.add(.tangent(line, arc))
            }
            sketch.add(.equal(left, right))
            sketch.add(.fix(leftCenter, at: .zero))
            sketch.add(.horizontal(top))
            length = sketch.addDimension(.distance(leftCenter, rightCenter), value: value)
            sketch.addDimension(.radius(left), value: radius)
        }
    }

    @Test func slotSolvesToZeroDegreesOfFreedom() throws {
        let slot = Slot()
        let solution = SketchSolver.solve(slot.sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[slot.rightCenter]), Vector2(40, 0)))
        let (_, topRight, topLeft) = (0, slot.sketch.ends(slot.top).0, slot.sketch.ends(slot.top).1)
        #expect(isClose(try #require(solution.points[topLeft]), Vector2(0, 5)))
        #expect(isClose(try #require(solution.points[topRight]), Vector2(40, 5)))
    }

    @Test func triangleByDimensionsIsThreeFourFive() throws {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [Vector2(0.4, 0.3), Vector2(4.5, -0.2), Vector2(3.6, 3.4)])
        let (a, b) = sketch.ends(lines[0])
        let c = sketch.ends(lines[1]).1
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.addDimension(.length(lines[0]), value: 4)
        sketch.addDimension(.length(lines[1]), value: 3)
        sketch.addDimension(.length(lines[2]), value: 5)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[b]), Vector2(4, 0)))
        // The right angle is at B and C stays above the base, where it was drawn.
        #expect(isClose(try #require(solution.points[c]), Vector2(4, 3)))
    }
}
