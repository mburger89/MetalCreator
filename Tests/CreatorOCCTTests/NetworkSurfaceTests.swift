#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 Task 2: the Gordon network surface.
struct NetworkSurfaceTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func line(_ a: Vector3, _ b: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(a, b)], tag: tag)
    }

    /// A quadratic Bezier through poles `a`, `b`, `c` (a parabola when `b` is the middle of the chord's tangents).
    func parabola(_ a: Vector3, _ b: Vector3, _ c: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.spline(BSplineCurve3D(degree: 2, poles: [a, b, c], knots: [0, 1], multiplicities: [3, 3]))],
                                   tag: tag)
    }

    /// Three lines each way over 10 mm x 10 mm at z = `lift` for the v curve numbered `liftedV` (nil: none lifted).
    func gridLines(liftedV: Int? = nil, lift: Double = 0) async throws -> (u: [Curve], v: [Curve]) {
        var u: [Curve] = []
        var v: [Curve] = []
        for y in [0.0, 5, 10] {
            u.append(try await line(Vector3(0, y, 0), Vector3(10, y, 0)))
        }
        for (index, x) in [0.0, 5, 10].enumerated() {
            let z = index == liftedV ? lift : 0
            v.append(try await line(Vector3(x, 0, z), Vector3(x, 10, z)))
        }
        return (u, v)
    }

    /// The saddle z = 0.1 x^2 - 0.1 y^2 over 10 mm x 10 mm: u curves at y = 0, 5, 10 and v curves at x = 0, 5, 10.
    func saddle() async throws -> (u: [Curve], v: [Curve]) {
        var u: [Curve] = []
        var v: [Curve] = []
        for y in [0.0, 5, 10] {
            let z = -0.1 * y * y
            // z = z0 + 0.1 x^2 with x = 10 t: the middle pole has the end tangent's height.
            u.append(try await parabola(Vector3(0, y, z), Vector3(5, y, z), Vector3(10, y, z + 10)))
        }
        for x in [0.0, 5, 10] {
            let z = 0.1 * x * x
            v.append(try await parabola(Vector3(x, 0, z), Vector3(x, 5, z), Vector3(x, 10, z - 10)))
        }
        return (u, v)
    }

    func maxMiss(_ curves: [Curve], _ sheet: Solid) async throws -> Double {
        var worst = 0.0
        for curve in curves {
            let distances = try await kernel.distances(from: curve.polyline, to: .solid(sheet), signed: false)
            worst = max(worst, distances.max() ?? 0)
        }
        return worst
    }

    @Test func aGridOfLinesIsTheirBilinearSurface() async throws {
        let (u, v) = try await gridLines()
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(sheet.topology.faces.count == 1)
        #expect(!sheet.isClosed)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 100, relative: 1e-9))
        #expect(abs(sheet.bounds.min.z) < 1e-5 && abs(sheet.bounds.max.z) < 1e-5)
    }

    @Test func aSaddleNetworkPassesThroughEveryCurve() async throws {
        let (u, v) = try await saddle()
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(sheet.topology.faces.count == 1)
        #expect(try await maxMiss(u + v, sheet) <= 1e-4)
        // z = 0.1 (x^2 - y^2), so the corner (10, 0) is 10 mm up and (0, 10) is 10 mm down.
        #expect(abs(sheet.bounds.max.z - 10) < 1e-6 && abs(sheet.bounds.min.z + 10) < 1e-6)
    }

    @Test func curvesThatMissAreNamed() async throws {
        let (u, v) = try await gridLines(liftedV: 2, lift: 0.5)
        await #expect {
            try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "u curve 1 and v curve 3 miss each other by 0.5 mm." }
    }

    @Test func nearlyMeetingCurvesBuild() async throws {
        let (u, v) = try await gridLines(liftedV: 2, lift: 0.005)
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(sheet.topology.faces.count == 1)
        #expect(try await maxMiss(u + v, sheet) <= 0.01)
    }

    @Test func shuffledAndReversedCurvesBuildTheSameSurface() async throws {
        let (u, v) = try await saddle()
        let ordered = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        // Reverse by rebuilding each parabola from its far end: poles reversed.
        func reversed(_ curve: Curve, _ poles: [Vector3]) async throws -> Curve {
            try await parabola(poles[2], poles[1], poles[0])
        }
        var u2: [Curve] = []
        var v2: [Curve] = []
        for (n, y) in [10.0, 0, 5].enumerated() {
            let z = -0.1 * y * y
            let poles = [Vector3(0, y, z), Vector3(5, y, z), Vector3(10, y, z + 10)]
            u2.append(n == 1 ? try await reversed(u[0], poles) : try await parabola(poles[0], poles[1], poles[2]))
        }
        for (n, x) in [5.0, 10, 0].enumerated() {
            let z = 0.1 * x * x
            let poles = [Vector3(x, 0, z), Vector3(x, 5, z), Vector3(x, 10, z - 10)]
            v2.append(n != 1 ? try await reversed(v[0], poles) : try await parabola(poles[0], poles[1], poles[2]))
        }
        let shuffled = try await kernel.networkSurface(u: u2, v: v2, tolerance: 0.01, tag: tag)
        let areaA = try await kernel.properties(of: ordered).surfaceArea
        let areaB = try await kernel.properties(of: shuffled).surfaceArea
        #expect(abs(areaA - areaB) < 1e-6)
        let mesh = try await kernel.tessellate(ordered, tolerance: 0.05)
        let away = try await kernel.distances(from: mesh.positions, to: .solid(shuffled), signed: false)
        #expect((away.max() ?? 1) < 1e-6)
    }

    @Test func crossingsAtDifferentParametersAreRefittedOntoTheNetwork() async throws {
        var u: [Curve] = []
        for y in [0.0, 5, 10] {
            u.append(try await line(Vector3(0, y, 0), Vector3(10, y, 0)))
        }
        // The middle curve leans, so it meets the u curves at x = 4, 5 and 6: parameters 0.4, 0.5 and 0.6.
        var v: [Curve] = []
        for (from, to) in [(0.0, 0.0), (4, 6), (10, 10)] {
            v.append(try await line(Vector3(from, 0, 0), Vector3(to, 10, 0)))
        }
        v.swapAt(0, 2)
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 100, relative: 1e-6))
        #expect(try await maxMiss(u + v, sheet) <= 1e-4)
    }

    @Test func aNetworkNeedsTwoCurvesEachWay() async throws {
        let (u, v) = try await gridLines()
        for (a, b) in [([u[0]], v), (u, [v[0]]), ([], v)] {
            await #expect {
                try await kernel.networkSurface(u: a, v: b, tolerance: 0.01, tag: tag)
            } throws: { message(of: $0) == "A network needs at least two curves in each direction." }
        }
    }

    @Test func aCurveCrossingTwiceIsRefused() async throws {
        let (u, v) = try await gridLines()
        // A v curve that overshoots y = 10 and comes back, so the line y = 10 meets it twice.
        let twice = try await parabola(Vector3(4, 0, 0), Vector3(6, 20, 0), Vector3(4, 10, 0))
        await #expect {
            try await kernel.networkSurface(u: u, v: [v[0], twice, v[2]], tolerance: 0.01, tag: tag)
        } throws: { message(of: $0)?.hasSuffix(" more than once.") == true }
    }

    @Test func namesTheBorders() async throws {
        let (u, v) = try await saddle()
        let sheet = try await kernel.networkSurface(u: u, v: v, tolerance: 0.01, tag: tag)
        #expect(sheet.topology.faces[0].tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))))
        func edges(_ role: BoundaryRole) -> [EdgeInfo] {
            sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(role) } }
        }
        #expect(edges(.start).count == 1 && edges(.end).count == 1)
        #expect(edges(.rail(0)).count == 1 && edges(.rail(1)).count == 1)
        // u curve 1 is y = 0, curve 3 is y = 10; v curve 1 is x = 0, v curve 3 is x = 10.
        #expect(edges(.start).allSatisfy { abs($0.midpoint.y) < 1e-6 })
        #expect(edges(.end).allSatisfy { abs($0.midpoint.y - 10) < 1e-6 })
        #expect(edges(.rail(0)).allSatisfy { abs($0.midpoint.x) < 1e-6 })
        #expect(edges(.rail(1)).allSatisfy { abs($0.midpoint.x - 10) < 1e-6 })
    }

    @Test func aRationalCurveIsRefused() async throws {
        let (u, v) = try await gridLines()
        let quarter = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: .pi / 2)
        let arc = try await kernel.makeCurve([quarter], tag: tag)
        await #expect {
            try await kernel.networkSurface(u: [u[0], arc, u[2]], v: v, tolerance: 0.01, tag: tag)
        } throws: { message(of: $0) == "Network curves can't be rational." }
    }
}
#endif
