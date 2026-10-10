import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorSketchEditor

/// The triangulation of a region's loops (sketcher spec §8's region fill): every triangle counter-clockwise, the
/// triangles' areas adding up to the outline's less the holes', none of them inside a hole.
struct RegionTriangulatorTests {
    func square(_ x: Double, _ y: Double, _ side: Double) -> [Vector2] {
        [Vector2(x, y), Vector2(x + side, y), Vector2(x + side, y + side), Vector2(x, y + side)]
    }

    func circle(_ centre: Vector2, _ radius: Double, steps: Int = 72) -> [Vector2] {
        (0..<steps).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(steps)
            return centre + Vector2(cos(angle), sin(angle)) * radius
        }
    }

    /// The polygon's area (positive for counter-clockwise).
    func area(_ loop: [Vector2]) -> Double {
        zip(loop, loop.dropFirst() + loop.prefix(1)).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) } / 2
    }

    func triangleAreas(_ points: [Vector2]) -> [Double] {
        stride(from: 0, to: points.count - 2, by: 3).map { area([points[$0], points[$0 + 1], points[$0 + 2]]) }
    }

    func contains(_ loop: [Vector2], _ p: Vector2) -> Bool {
        var inside = false
        for (a, b) in zip(loop, loop.dropFirst() + loop.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Checks what every triangulation must satisfy and returns the triangles.
    @discardableResult
    func check(outer: [Vector2], holes: [[Vector2]], sourceLocation: SourceLocation = #_sourceLocation) -> [Vector2] {
        let points = RegionTriangulator.triangles(outer: outer, holes: holes)
        #expect(points.count % 3 == 0, sourceLocation: sourceLocation)
        let areas = triangleAreas(points)
        #expect(areas.allSatisfy { $0 > 0 }, "every triangle runs counter-clockwise", sourceLocation: sourceLocation)
        let expected = abs(area(outer)) - holes.reduce(0) { $0 + abs(area($1)) }
        #expect(abs(areas.reduce(0, +) - expected) < 1e-6 * max(1, expected), "the areas add up", sourceLocation: sourceLocation)
        for (index, area) in areas.enumerated() {
            let corners = Array(points[3 * index..<3 * index + 3])
            let centroid = (corners[0] + corners[1] + corners[2]) * (1.0 / 3)
            #expect(contains(outer, centroid) && !holes.contains { contains($0, centroid) },
                    "triangle \(index) (area \(area)) lies in the region", sourceLocation: sourceLocation)
        }
        return points
    }

    @Test func aSquareIsTwoTriangles() {
        #expect(check(outer: square(0, 0, 10), holes: []).count == 6)
    }

    @Test func aConcaveOutlineFills() {
        let l = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10), Vector2(10, 20), Vector2(0, 20)]
        #expect(check(outer: l, holes: []).count == 12, "n − 2 triangles")
    }

    @Test func loopsInEitherWindingGiveTheSameFill() {
        let hole = square(5, 5, 5)
        let forward = check(outer: square(0, 0, 20), holes: [hole])
        let backward = check(outer: Array(square(0, 0, 20).reversed()), holes: [Array(hole.reversed())])
        #expect(triangleAreas(forward).reduce(0, +) == triangleAreas(backward).reduce(0, +))
    }

    @Test func aSquareHoleLeavesTheHoleEmpty() {
        #expect(check(outer: square(0, 0, 20), holes: [square(5, 5, 10)]).count == 24, "4 + 4 + 2 − 2 triangles")
    }

    @Test func aCircularHoleLeavesTheHoleEmpty() {
        check(outer: square(0, 0, 40), holes: [circle(Vector2(20, 20), 8)])
    }

    @Test func severalHolesAreAllCutOut() {
        check(outer: square(0, 0, 60), holes: [circle(Vector2(15, 30), 8), square(30, 10, 10), circle(Vector2(45, 40), 6, steps: 24)])
    }

    @Test func aHoleNearACornerAndOneTouchingTheOutlinesLineOfSightStillFill() {
        check(outer: square(0, 0, 20), holes: [square(1, 1, 4), square(14, 14, 4)])
        let notch = [Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(20, 30), Vector2(20, 10), Vector2(10, 10),
                     Vector2(10, 30), Vector2(0, 30),
        ]
        check(outer: notch, holes: [square(2, 2, 4), square(22, 14, 4)])
    }

    /// An n × n grid of 10 mm square holes, 10 mm apart, in a plate with a 10 mm margin.
    func gridHoles(_ count: Int) -> (outer: [Vector2], holes: [[Vector2]]) {
        let side = Double(count) * 20 + 10
        let holes = (0..<count).flatMap { column in
            (0..<count).map { row in square(10 + Double(column) * 20, 10 + Double(row) * 20, 10) }
        }
        return (square(0, 0, side), holes)
    }

    @Test(arguments: 2...5) func aGridOfAlignedSquareHolesLeavesEveryHoleEmpty(count: Int) {
        let (outer, holes) = gridHoles(count)
        let points = check(outer: outer, holes: holes)
        let side = Double(count) * 20 + 10
        #expect(abs(triangleAreas(points).reduce(0, +) - (side * side - Double(count * count) * 100)) < 1e-6)
    }

    @Test func holesSharingAnEdgeLineWithEachOtherAndTheOutlineStillFill() {
        check(outer: square(0, 0, 50), holes: [square(10, 10, 10), square(30, 10, 10), square(10, 30, 10)])
        check(outer: square(0, 0, 50), holes: [square(10, 10, 10), square(10, 30, 10), square(30, 20, 10)])
        check(outer: square(0, 0, 60), holes: [square(10, 10, 10), square(10, 30, 20), square(40, 10, 10), square(40, 30, 10)])
    }

    @Test func aHoleThatCantBeBridgedGivesNoFillRatherThanAWrongOne() {
        #expect(RegionTriangulator.triangles(outer: square(0, 0, 10), holes: [square(8, 8, 5)]).isEmpty, "a hole crossing the outline")
    }

    @Test func degenerateInputGivesNoTrianglesAndNeverHangs() {
        #expect(RegionTriangulator.triangles(outer: [], holes: []).isEmpty)
        #expect(RegionTriangulator.triangles(outer: [Vector2(0, 0), Vector2(1, 0)], holes: []).isEmpty)
        #expect(RegionTriangulator.triangles(outer: [Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)], holes: []).isEmpty, "collinear")
        #expect(RegionTriangulator.triangles(outer: square(0, 0, 10), holes: [[Vector2(2, 2), Vector2(3, 3)]]).count == 6,
                "a hole of two points is no hole")
    }

    @Test func polylinesFollowLinesAndArcsAndDropRepeatedPoints() {
        let lines: [Segment2D] = [.line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 10)),
                                  .line(Vector2(10, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        #expect(RegionTriangulator.polyline(lines) == square(0, 0, 10))
        let full: [Segment2D] = [.arc(center: Vector2(5, 5), radius: 3, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))]
        let ring = RegionTriangulator.polyline(full)
        #expect(ring.count == EditorGeometry.segmentsPerTurn)
        #expect(ring.allSatisfy { abs((Vector2(5, 5) - $0).length - 3) < 1e-9 })
        let half: [Segment2D] = [.arc(center: .zero, radius: 10, start: Angle(radians: 0), end: Angle(radians: .pi)),
                                 .line(Vector2(-10, 0), Vector2(10, 0)),
        ]
        let d = RegionTriangulator.polyline(half)
        #expect(d.count == EditorGeometry.segmentsPerTurn / 2 + 1, "half a turn's steps, then the line's start")
        #expect(area(d) > 0 && abs(area(d) - Double.pi * 50) < 1)
    }
}
