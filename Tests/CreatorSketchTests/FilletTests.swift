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

    @Test(arguments: [60.0, 120.0, 30.0, 150.0])
    func filletGeometryAtNonRightAnglesMatchesTheClosedForm(degrees: Double) throws {
        let radius = 2.0
        let angle = degrees * .pi / 180
        let direction = Vector2(cos(angle), sin(angle))
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        let firstLine = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        sketch.addLine(from: corner, to: sketch.addPoint(direction * 10))
        let filleted = try SketchCommands.fillet(sketch, corner: corner, radius: radius).sketch
        let arc = try #require(filleted.ids(ofKind: "Arc").first)
        let (center, start, end) = filleted.arcPoints(arc)
        let centerPosition = try #require(filleted.position(of: center))
        let startPosition = try #require(filleted.position(of: start))
        let endPosition = try #require(filleted.position(of: end))
        let half = angle / 2
        let setback = radius / tan(half)
        let bisector = Vector2(cos(half), sin(half))
        #expect(isClose(centerPosition, bisector * (radius / sin(half))))
        #expect(isClose(startPosition.length, setback) && isClose(endPosition.length, setback))
        #expect(isClose(startPosition, Vector2(setback, 0)) || isClose(endPosition, Vector2(setback, 0)))
        #expect(isClose(startPosition, direction * setback) || isClose(endPosition, direction * setback))
        // The center is one radius from both lines and from both tangent points.
        #expect(isClose(abs(centerPosition.y), radius))
        #expect(isClose(abs(SketchMath.cross(direction, centerPosition)), radius))
        #expect(isClose((startPosition - centerPosition).length, radius))
        #expect(isClose((endPosition - centerPosition).length, radius))
        // The tangent points sit on the (trimmed) lines, which now end there.
        let trimmedEnd = filleted.ends(firstLine).0
        #expect(trimmedEnd == start || trimmedEnd == end)
        // Two lines and a free polyline carry no dimensions, so the solve is usable but not fully constrained.
        _ = try requireSolvesInPlace(filleted)
    }

    @Test(arguments: [(60.0, "5.8"), (120.0, "17.3"), (30.0, "2.7")])
    func tooLargeARadiusAtNonRightAnglesReportsTheAngleDependentMaximum(degrees: Double, largest: String) {
        let angle = degrees * .pi / 180
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(cos(angle), sin(angle)) * 10))
        #expect(throws: SketchCommandError("Radius 30 mm is too large for this corner (max ≈ \(largest) mm).")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 30)
        }
    }

    @Test func filletingAClockwiseCornerPicksTheShortArc() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        // Corner 0 (the origin): line 0 then line 3 gives a clockwise short arc.
        let corner = rectangle.sketch.ends(rectangle.lines[0]).0
        let edit = try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5)
        let filleted = edit.sketch
        let arc = try #require(filleted.ids(ofKind: "Arc").first)
        let (center, start, end) = filleted.arcPoints(arc)
        let centerPosition = try #require(filleted.position(of: center))
        let startPosition = try #require(filleted.position(of: start))
        let endPosition = try #require(filleted.position(of: end))
        #expect(isClose(centerPosition, Vector2(5, 5)))
        // Arcs run counter-clockwise from start to end, so the short arc starts on the left edge.
        #expect(isClose(startPosition, Vector2(0, 5)))
        #expect(isClose(endPosition, Vector2(5, 0)))
        #expect(isClose(SketchMath.cross(startPosition - centerPosition, endPosition - centerPosition), 25))
        let region = try #require(SketchRegions.find(in: filleted).regions.first)
        #expect(isClose(region.area, 2400 - (25 - 25 * .pi / 4), tolerance: 1e-6))
        // The fillet removed the origin's fix and both lines' lengths, so the sketch is usable but no longer fully constrained.
        let solution = try requireSolvesInPlace(filleted)
        #expect(solution.status == .underConstrained(dof: 4))
        // The edit says what it removed, and the radius never takes a removed dimension's name.
        let fix = try #require(rectangle.sketch.constraintIDs.first { if case .fix = rectangle.sketch.constraints[$0] { true } else { false } })
        #expect(edit.removed == [.constraint(fix), .dimension(rectangle.width), .dimension(rectangle.height)])
        let radius = try #require(filleted.dimensions.values.first { if case .radius = $0.kind { true } else { false } })
        #expect(radius.name == "d3")
    }

    /// Removing an exposed dimension would leave its graph socket dangling, so the command refuses.
    @Test func filletingACornerWithAnExposedDimensionIsRefused() {
        var rectangle = ConstrainedRectangle(drawnOffset: 0)
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = true
        let corner = rectangle.sketch.ends(rectangle.lines[0]).0
        #expect(throws: SketchCommandError("That would remove d1, which is exposed as an input. Stop exposing it first.")) {
            try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5)
        }
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
