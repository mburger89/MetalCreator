import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct FilletTests {
    @Test func filletingARectangleCornerStaysFullyConstrained() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        let (right, top) = (rectangle.lines[1], rectangle.lines[2])
        let corner = rectangle.sketch.ends(right).1
        let edit = try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5)
        let filleted = edit.sketch
        #expect(edit.description == "Fillet Point 3 (5 mm)")
        #expect(filleted.entities[corner] == nil)
        let arc = try #require(filleted.ids(ofKind: "Arc").first)
        let (center, start, end) = filleted.arcPoints(arc)
        #expect(isClose(try #require(filleted.position(of: center)), Vector2(55, 35)))
        #expect(isClose(try #require(filleted.position(of: start)), Vector2(60, 35)))
        #expect(isClose(try #require(filleted.position(of: end)), Vector2(55, 40)))
        #expect(filleted.ends(right).1 == start)
        #expect(filleted.ends(top).0 == end)
        let constraints = filleted.constraintList
        #expect(constraints.contains(.tangent(right, arc)))
        #expect(constraints.contains(.tangent(top, arc)))
        #expect(filleted.dimensions.values.contains { $0.kind == .radius(arc) && $0.value == 5 && $0.name == "d3" })
        let solution = try requireSolvesInPlace(filleted)
        #expect(solution.status == .solved)
    }

    @Test func filletRegionHasTheRoundedArea() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        let corner = rectangle.sketch.ends(rectangle.lines[1]).1
        let filleted = try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5).sketch
        let region = try #require(SketchRegions.find(in: filleted).regions.first)
        #expect(isClose(region.area, 2400 - (25 - 25 * .pi / 4), tolerance: 1e-6))
    }

    @Test func tooLargeARadiusNamesTheLargestThatFits() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(0, 20)))
        #expect(throws: SketchCommandError("Radius 15 mm is too large for this corner (max ≈ 10 mm).")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 15)
        }
    }

    @Test func aFilletNeedsExactlyTwoLines() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        for end in [Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)] {
            sketch.addLine(from: corner, to: sketch.addPoint(end))
        }
        #expect(throws: SketchCommandError("A fillet needs a corner where exactly two lines meet.")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 1)
        }
    }

    @Test func straightThroughLinesCantBeFilleted() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        sketch.addLine(from: sketch.addPoint(Vector2(-10, 0)), to: corner)
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        #expect(throws: SketchCommandError("The lines at that corner are parallel.")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 1)
        }
    }
}
