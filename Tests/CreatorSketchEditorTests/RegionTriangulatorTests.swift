import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorSketchEditor

/// A region's polylines (the triangulation itself is `PolygonTriangulatorTests`).
struct RegionTriangulatorTests {
    func square(_ x: Double, _ y: Double, _ side: Double) -> [Vector2] {
        [Vector2(x, y), Vector2(x + side, y), Vector2(x + side, y + side), Vector2(x, y + side)]
    }

    func area(_ loop: [Vector2]) -> Double {
        zip(loop, loop.dropFirst() + loop.prefix(1)).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) } / 2
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
