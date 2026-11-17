#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-1 Task 2: curves in OpenCascade.
struct CurveKernelTests {
    let tag = newTag()

    func helix(_ count: Int) -> [Vector3] {
        (0..<count).map { i in
            let t = Double(i) * 0.8
            return Vector3(5 * cos(t), 5 * sin(t), 1.5 * t)
        }
    }

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    @Test func aClosedRectangleIsOnePlanarClosedCurve() async throws {
        let (a, b, c, d) = (Vector3(0, 0, 0), Vector3(12, 0, 0), Vector3(12, 8, 0), Vector3(0, 8, 0))
        let curve = try await OCCTKernel().makeCurve([.line(a, b), .line(b, c), .line(c, d), .line(d, a)], tag: tag)
        #expect(curve.isClosed)
        #expect(curve.pieceCount == 4)
        #expect(abs(curve.length - 40) < 1e-9)
        let plane = try #require(curve.plane)
        #expect(abs(abs(plane.normal.dot(.unitZ)) - 1) < 1e-9)
        #expect(abs(curve.bounds.max.x - 12) < 1e-5 && abs(curve.bounds.min.y) < 1e-5)
        #expect(curve.polyline.count == 5)
    }

    @Test func anOpenCurveIsNotClosed() async throws {
        let curve = try await OCCTKernel().makeCurve([.line(.zero, Vector3(3, 4, 0))], tag: tag)
        #expect(!curve.isClosed)
        #expect(abs(curve.length - 5) < 1e-9)
    }

    @Test func aFullCircleArcIsClosed() async throws {
        let start = Vector3(5, 0, 0)
        let curve = try await OCCTKernel().makeCurve(
            [.arc(center: .zero, normal: .unitZ, radius: 5, start: start, sweep: 2 * .pi)], tag: tag)
        #expect(curve.isClosed)
        #expect(abs(curve.length - 10 * .pi) < 1e-6)
        #expect(curve.plane != nil)
    }

    @Test func aClockwiseArcRunsTheOtherWay() async throws {
        let curve = try await OCCTKernel().makeCurve(
            [.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: -.pi / 2)], tag: tag)
        #expect(abs(curve.length - 2.5 * .pi) < 1e-6)
        let end = try #require(curve.polyline.last)
        #expect((end - Vector3(0, -5, 0)).length < 1e-6)
    }

    @Test func piecesThatDontJoinAreRefused() async throws {
        await #expect(throws: KernelError.invalidInput("The curve's pieces don't join end to end.")) {
            try await OCCTKernel().makeCurve([.line(.zero, Vector3(1, 0, 0)), .line(Vector3(2, 0, 0), Vector3(3, 0, 0))], tag: tag)
        }
    }

    @Test func aMalformedSplineIsRefused() async throws {
        let empty = BSplineCurve3D(degree: 5, poles: [], knots: [0, 1], multiplicities: [6, 6])
        let counts = BSplineCurve3D(degree: 3, poles: [.zero, .unitX, .unitY, .unitZ], knots: [0, 1], multiplicities: [3, 3])
        let degree = BSplineCurve3D(degree: 0, poles: [.zero, .unitX], knots: [0, 1], multiplicities: [1, 1])
        for spline in [empty, counts, degree] {
            await #expect(throws: KernelError.invalidInput("The curve's spline is malformed.")) {
                try await OCCTKernel().makeCurve([.spline(spline)], tag: tag)
            }
        }
    }

    @Test func interpolateDegree3PassesThroughEveryPoint() async throws {
        let kernel = OCCTKernel()
        let points = helix(6)
        let curve = try await kernel.interpolate(points, degree: 3, closed: false, startTangent: nil, endTangent: nil, tag: tag)
        #expect(!curve.isClosed && curve.plane == nil)
        for point in points {
            #expect(try await kernel.distance(from: point, to: curve) < 1e-6)
        }
    }

    @Test func interpolateWithEndTangentsLeavesAlongThem() async throws {
        let kernel = OCCTKernel()
        let points = [Vector3(0, 0, 0), Vector3(5, 5, 0), Vector3(10, 0, 0)]
        let curve = try await kernel.interpolate(points, degree: 3, closed: false, startTangent: Vector3(0, 1, 0),
                                                 endTangent: Vector3(0, -1, 0), tag: tag)
        let second = try #require(curve.polyline.dropFirst().first)
        #expect(abs(second.x) < 0.5 * abs(second.y))
        for point in points {
            #expect(try await kernel.distance(from: point, to: curve) < 1e-6)
        }
    }

    @Test func aClosedInterpolationIsClosedAndPassesThroughItsPoints() async throws {
        let kernel = OCCTKernel()
        let points = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)]
        let curve = try await kernel.interpolate(points, degree: 3, closed: true, startTangent: nil, endTangent: nil, tag: tag)
        #expect(curve.isClosed)
        for point in points {
            #expect(try await kernel.distance(from: point, to: curve) < 1e-6)
        }
    }

    @Test func interpolateDegree5PassesThroughEightHelixPoints() async throws {
        let kernel = OCCTKernel()
        let points = helix(8)
        let curve = try await kernel.interpolate(points, degree: 5, closed: false, startTangent: nil, endTangent: nil, tag: tag)
        for point in points {
            #expect(try await kernel.distance(from: point, to: curve) < 1e-6)
        }
    }

    @Test func degree5NeedsSixPoints() async throws {
        await #expect(throws: KernelError.invalidInput("A degree-5 curve needs at least six points.")) {
            try await OCCTKernel().interpolate(helix(5), degree: 5, closed: false, startTangent: nil, endTangent: nil, tag: tag)
        }
    }

    /// OpenCascade's degree-5 fit reproduces every input point (the worst gap over zigzags, random clouds, near-coincident and
    /// backtracking points was far under 1e-6 mm), so no input misses by 1e-6 mm. The check is proved with a tiny threshold on
    /// points the fit leaves 1e-12 mm or more from the curve; the same points pass at 1e-6 mm.
    static let nearlyCoincident = [
        Vector3(0, 0, 0), Vector3(0.001, 0, 0), Vector3(10, 0, 0), Vector3(10.001, 5, 0), Vector3(20, 0, 0), Vector3(30, 9, 3),
    ]

    @Test func degree5RefusesWhenTheCurveMissesByMoreThanTheThreshold() async throws {
        let kernel = OCCTKernel()
        let error = try #require(await #expect(throws: KernelError.self) {
            try await kernel.interpolate(Self.nearlyCoincident, degree: 5, closed: false, startTangent: nil,
                                         endTangent: nil, maxDeviation: 1e-13)
        })
        #expect(message(of: error) == "The curve can't pass through these points at degree 5; try degree 3.")
    }

    @Test func theSamePointsPassAtTheRealThreshold() async throws {
        let kernel = OCCTKernel()
        let curve = try await kernel.interpolate(Self.nearlyCoincident, degree: 5, closed: false, startTangent: nil,
                                                 endTangent: nil, tag: tag)
        for point in Self.nearlyCoincident {
            #expect(try await kernel.distance(from: point, to: curve) < 1e-6)
        }
    }

    @Test func twoCoincidentPointsAreRefused() async throws {
        let points = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]
        await #expect(throws: KernelError.invalidInput("Points 2 and 3 are in the same place.")) {
            try await OCCTKernel().interpolate(points, degree: 3, closed: false, startTangent: nil, endTangent: nil, tag: tag)
        }
    }

    @Test func curvesFromTheTopEdgesOfABox() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 12, 8, 5, tag: tag)
        let top = solid.topology.edges.filter { abs($0.midpoint.z - 5) < 1e-9 }
        #expect(top.count == 4)
        let curves = try await kernel.curves(from: top.map(\.id), of: solid, tag: tag)
        #expect(curves.count == 1)
        let curve = try #require(curves.first)
        #expect(curve.isClosed && curve.pieceCount == 4)
        #expect(abs(curve.length - 40) < 1e-9)
        #expect(curve.plane != nil)
    }

    @Test func twoDisjointLoopsGiveTwoCurvesInOrderOfTheirLowestEdge() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 12, 8, 5, tag: tag)
        let low = solid.topology.edges.filter { abs($0.midpoint.z) < 1e-9 }
        let high = solid.topology.edges.filter { abs($0.midpoint.z - 5) < 1e-9 }
        let all = low + high
        let lowest = all.map(\.id.rawValue).min()
        let curves = try await kernel.curves(from: all.map(\.id), of: solid, tag: tag)
        #expect(curves.count == 2)
        let firstIsLow = low.map(\.id.rawValue).contains(try #require(lowest))
        #expect(curves.allSatisfy { $0.isClosed })
        let firstZ = try #require(curves.first?.polyline.first?.z)
        #expect(abs(firstZ - (firstIsLow ? 0 : 5)) < 1e-9)
    }

    @Test func aMissingEdgeIsRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 12, 8, 5, tag: tag)
        await #expect(throws: KernelError.invalidInput("That edge no longer exists.")) {
            try await kernel.curves(from: [EdgeID(99)], of: solid, tag: tag)
        }
    }

    @Test func aSplinePieceRoundTrips() async throws {
        let sketch = SplineDefinition(points: [Vector2(0, 0), Vector2(5, 4), Vector2(10, -2), Vector2(15, 3)]).curve()
        let spline = BSplineCurve3D(degree: sketch.degree, poles: sketch.poles.map { Vector3($0.x, $0.y, 0) },
                                    knots: sketch.knots, multiplicities: sketch.multiplicities)
        let curve = try await OCCTKernel().makeCurve([.spline(spline)], tag: tag)
        #expect(curve.pieceCount == 1 && !curve.isClosed)
        let ends = try #require(curve.polyline.first)
        #expect((ends - Vector3(0, 0, 0)).length < 1e-9)
        #expect((try #require(curve.polyline.last) - Vector3(15, 3, 0)).length < 1e-9)
        #expect(curve.length > 15)
    }
}
#endif
