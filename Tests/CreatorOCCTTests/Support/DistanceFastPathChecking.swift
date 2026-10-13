import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// What the distance fast path's tests share: the fixtures and the comparison with `BRepExtrema` alone.
protocol DistanceFastPathChecking {}

extension DistanceFastPathChecking {
    var tolerance: Double { 1e-9 }

    func plate(_ kernel: OCCTKernel, holes: [[Segment2D]] = []) async throws -> OCCTShape {
        var profile = Profile2D.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy)
        profile.holes = holes
        let solid = try await kernel.extrude(profile, distance: 6, mode: .oneSided, tag: newTag())
        return try await kernel.shape(of: solid)
    }

    func circleLoop(at center: Vector2, radius: Double) -> [Segment2D] {
        [.arc(center: center, radius: radius, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))]
    }

    /// Points on a regular grid (so some fall exactly on edges, corner-arc ends and faces) over the region round `bounds`.
    func grid(x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>, step: Double) -> [Vector3] {
        var points: [Vector3] = []
        for xi in stride(from: x.lowerBound, through: x.upperBound, by: step) {
            for yi in stride(from: y.lowerBound, through: y.upperBound, by: step) {
                for zi in stride(from: z.lowerBound, through: z.upperBound, by: step) { points.append(Vector3(xi, yi, zi)) }
            }
        }
        return points
    }

    func expectAgreement(_ shape: OCCTShape, _ points: [Vector3], kind: OCCTShape.DistanceKind = .surface, indices: [Int32] = [],
                         signed: Bool, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (fast, reference) = try OCCTKernel.serialized { () throws -> ([Double], [Double]) in
            (try shape.distances(from: points[...], kind: kind, indices: indices, signed: signed),
             try shape.distancesByExtrema(from: points[...], kind: kind, indices: indices, signed: signed))
        }
        #expect(fast.count == points.count && reference.count == points.count, sourceLocation: sourceLocation)
        var worst = 0.0
        var worstPoint = Vector3.zero
        for (index, point) in points.enumerated() where abs(fast[index] - reference[index]) > worst {
            worst = abs(fast[index] - reference[index])
            worstPoint = point
        }
        #expect(worst <= tolerance, "the fast path and BRepExtrema differ by \(worst) at \(worstPoint)", sourceLocation: sourceLocation)
    }
}

extension DistanceFastPathChecking {
    /// `point` and the points one and two units in the last place either side of it in x and in y: the values a shared
    /// corner's two neighbours may disagree about.
    func nudged(_ point: Vector3) -> [Vector3] {
        var points = [point]
        for steps in 1...2 {
            var (up, down) = (point.x, point.x)
            var (upY, downY) = (point.y, point.y)
            for _ in 0..<steps {
                up = up.nextUp
                down = down.nextDown
                upY = upY.nextUp
                downY = downY.nextDown
            }
            points += [
                Vector3(up, point.y, point.z), Vector3(down, point.y, point.z),
                       Vector3(point.x, upY, point.z), Vector3(point.x, downY, point.z),
            ]
        }
        return points
    }

    /// A deterministic spread of `count` points over the box, from a fixed linear congruential sequence.
    func scattered(_ count: Int, x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>) -> [Vector3] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        return (0..<count).map { _ in
            Vector3(x.lowerBound + next() * (x.upperBound - x.lowerBound), y.lowerBound + next() * (y.upperBound - y.lowerBound),
                    z.lowerBound + next() * (z.upperBound - z.lowerBound))
        }
    }
}
