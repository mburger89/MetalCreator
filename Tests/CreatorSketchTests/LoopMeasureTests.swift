import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Exact loop area, moments and containment (Green's theorem), the basis of nesting and order.
struct LoopMeasureTests {
    func line(_ a: Vector2, _ b: Vector2) -> LoopSegment { LoopSegment(geometry: .line(a, b), source: 0) }
    func arc(_ c: Vector2, _ r: Double, _ from: Double, _ to: Double) -> LoopSegment {
        LoopSegment(geometry: .arc(center: c, radius: r, from: from, to: to), source: 0)
    }

    /// The upper half disk of radius 3, with the arc's ends at the exact vertices (±3, 0).
    var halfDisk: [LoopSegment] {
        [LoopSegment(geometry: .arc(center: .zero, radius: 3, from: 0, to: .pi), source: 0, start: Vector2(3, 0), end: Vector2(-3, 0)),
         line(Vector2(-3, 0), Vector2(3, 0))]
    }

    var square: [LoopSegment] {
        [line(.zero, Vector2(4, 0)), line(Vector2(4, 0), Vector2(4, 4)), line(Vector2(4, 4), Vector2(0, 4)), line(Vector2(0, 4), .zero)]
    }

    @Test func squareAreaAndCentroid() {
        #expect(LoopMeasure.area(square) == 16)
        #expect(LoopMeasure.moments(square) == Vector2(32, 32))
        #expect(LoopMeasure.area(square.reversed().map { segment in
            guard case .line(let a, let b) = segment.geometry else { return segment }
            return line(b, a)
        }) == -16)
    }

    @Test func offCentreCircleAreaAndCentroid() {
        let disk = [arc(Vector2(3, -2), 2, 0, 2 * .pi)]
        #expect(isClose(LoopMeasure.area(disk), 4 * .pi, tolerance: 1e-12))
        let moments = LoopMeasure.moments(disk)
        #expect(isClose(moments * (1 / LoopMeasure.area(disk)), Vector2(3, -2), tolerance: 1e-12))
        // Clockwise, the same circle has negative area.
        #expect(isClose(LoopMeasure.area([arc(Vector2(3, -2), 2, 2 * .pi, 0)]), -4 * .pi, tolerance: 1e-12))
    }

    @Test func halfDiskCentroidIsFourROverThreePi() {
        let half = halfDisk
        let area = LoopMeasure.area(half)
        #expect(isClose(area, 4.5 * .pi, tolerance: 1e-12))
        let centroid = LoopMeasure.moments(half) * (1 / area)
        #expect(isClose(centroid, Vector2(0, 4 * 3 / (3 * .pi)), tolerance: 1e-12))
    }

    @Test func containmentFollowsArcsExactly() {
        let half = halfDisk
        #expect(LoopMeasure.contains(half, Vector2(0, 2.9)))
        #expect(!LoopMeasure.contains(half, Vector2(0, 3.1)))
        #expect(!LoopMeasure.contains(half, Vector2(0, -0.1)))
        // Level with the arc's start: the half-open rule counts the vertex once.
        #expect(!LoopMeasure.contains(half, Vector2(-4, 0)))
        #expect(LoopMeasure.contains(square, Vector2(2, 2)))
        #expect(!LoopMeasure.contains(square, Vector2(5, 2)))
    }
}
