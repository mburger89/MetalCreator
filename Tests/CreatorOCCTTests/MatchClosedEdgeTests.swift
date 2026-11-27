#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-G Task 3: Match Surface on a closed edge (R5): a tube's rim to another tube's rim.
struct MatchClosedEdgeTests {
    let tag = newTag()
    let kernel = OCCTKernel()
    let closedToOpen = "Match Surface can't match a closed edge to an open one."

    /// The tube of radius `radius` about z, z from `from` to `to`, its seam at `start` degrees, revolved the other way when `reversed`.
    func tube(radius: Double = 10, from: Double = 0, to: Double = 20, start: Double = 0, reversed: Bool = false) async throws -> Solid {
        let a = start * .pi / 180
        let line = try await kernel.makeCurve(
            [.line(Vector3(radius * cos(a), radius * sin(a), from), Vector3(radius * cos(a), radius * sin(a), to))], tag: tag)
        return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: reversed ? Vector3(0, 0, -1) : .unitZ),
                                  angle: .degrees(360), tag: tag)
    }

    /// The rim of `tube` at z.
    func rim(_ tube: Solid, z: Double) throws -> EdgeInfo {
        try #require(tube.topology.edges.first { $0.faces.count == 1 && abs($0.midpoint.z - z) < 1e-6 })
    }

    /// The matched rim of `result`: the lower of its two single-face edges.
    func matchedRim(_ result: Solid) throws -> EdgeInfo {
        let rims = result.topology.edges.filter { $0.faces.count == 1 }
        #expect(rims.count == 2)
        return try #require(rims.min { $0.midpoint.z < $1.midpoint.z })
    }

    func openSheet() async throws -> (sheet: Solid, edge: EdgeInfo) {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 10, 0))], tag: tag)
        let sheet = try await kernel.revolve(line, axis: Axis(origin: Vector3(0, 0, 17.3205), direction: Vector3(0, -1, 0)),
                                             angle: .degrees(60), tag: tag)
        let edge = try #require(sheet.topology.edges.first {
            $0.kind == .line && abs($0.midpoint.x - 10) < 1e-6 && abs($0.midpoint.z) < 1e-6
        })
        return (sheet, edge)
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return "other: \(error)" }
        return nil
    }

    @Test func theEvaluatorReadsATube() async throws {
        let net = try await kernel.controlNet(of: try await tube()).surface
        #expect(net.isPeriodicU)
        let sheet = PeriodicSheet(net)
        for i in 0..<12 {
            let u = 2 * Double.pi * Double(i) / 12
            let p = sheet.point(u: u, v: 3, seam: .start)
            #expect(abs(hypot(p.x, p.y) - 10) < 1e-9 && abs(p.z - 3) < 1e-9, "u \(u) \(p)")
        }
    }

    /// The result, matched to a closed rim: its rim lies on the target, it grades as asked, it is periodic along the rim, and no
    /// ruling is twisted (each lands within 1 mm of the point nearest its own start).
    func check(_ result: Solid, from source: Solid, target: Solid, targetRim: EdgeInfo, continuity: PatchContinuity) async throws {
        let before = PeriodicSheet(try await kernel.controlNet(of: source).surface)
        let net = try await kernel.controlNet(of: result).surface
        #expect(net.isPeriodicU, "the result stays periodic along the rim")
        let sheet = PeriodicSheet(net)
        for i in 0..<64 {
            let u = 2 * Double.pi * Double(i) / 64
            let gap = try await kernel.shortestDistance(between: .point(sheet.point(u: u, v: 0, seam: .start)),
                                                        and: .edge(target, targetRim.id)).distance
            #expect(gap <= 1e-4, "u \(u) gap \(gap)")
        }
        let found = try await kernel.continuity(of: try matchedRim(result).id, in: result, against: FaceID(0), of: target)
        let wanted: ContinuityClass = continuity == .g2 ? .g2 : continuity == .g1 ? .g1 : .g0
        #expect(found.grade >= wanted, "angle \(found.angleGap) curvature \(found.curvatureGap)")
        #expect(found.positionGap <= 1e-4)
        // Periodic: both sides of the seam agree, in position and across the edge.
        for v in [0.0, 0.5, 4, 19.5] {
            let first = sheet.point(u: sheet.uFirst, v: v, seam: .start), last = sheet.point(u: sheet.uLast, v: v, seam: .end)
            #expect((first - last).length < 1e-7, "v \(v)")
            let h = 1e-4
            let across1 = (sheet.point(u: sheet.uFirst, v: v + h, seam: .start) - first) * (1 / h)
            let across2 = (sheet.point(u: sheet.uLast, v: v + h, seam: .end) - last) * (1 / h)
            #expect((across1 - across2).length < 1e-6, "v \(v)")
        }
        // No twist.
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let u = sheet.uFirst + fraction * (sheet.uLast - sheet.uFirst)
            let was = before.point(u: u, v: 0, seam: .start)
            let angle = atan2(was.y, was.x)
            let nearest = Vector3(12 * cos(angle), 12 * sin(angle), -5)
            let end = sheet.point(u: u, v: 0, seam: .start)
            #expect((end - nearest).length < 1, "u \(u) lands \(end)")
        }
    }

    @Test(arguments: [PatchContinuity.g0, .g1, .g2])
    func aTubeRimMatchesAClosedRim(continuity: PatchContinuity) async throws {
        let source = try await tube()
        let target = try await tube(radius: 12, from: -5, to: -25)
        let result = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: try rim(target, z: -5).id, of: target,
                                              continuity: continuity)
        try await check(result, from: source, target: target, targetRim: try rim(target, z: -5), continuity: continuity)
    }

    @Test func aFarSeamDoesNotTwist() async throws {
        let source = try await tube()
        let target = try await tube(radius: 12, from: -5, to: -25, start: 137)
        let result = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: try rim(target, z: -5).id, of: target,
                                              continuity: .g1)
        try await check(result, from: source, target: target, targetRim: try rim(target, z: -5), continuity: .g1)
    }

    @Test func aReversedTargetDoesNotTwist() async throws {
        let source = try await tube()
        let target = try await tube(radius: 12, from: -5, to: -25, reversed: true)
        let result = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: try rim(target, z: -5).id, of: target,
                                              continuity: .g2)
        try await check(result, from: source, target: target, targetRim: try rim(target, z: -5), continuity: .g2)
    }

    @Test func aClosedEdgeToAnOpenOneRefuses() async throws {
        let source = try await tube()
        let (sheet, edge) = try await openSheet()
        let text = await refusal {
            _ = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: edge.id, of: sheet, continuity: .g1)
        }
        #expect(text == closedToOpen)
    }

    @Test func anOpenEdgeToAClosedOneRefuses() async throws {
        let target = try await tube(radius: 12, from: -5, to: -25)
        let (sheet, edge) = try await openSheet()
        let text = await refusal {
            _ = try await kernel.matched(sheet, edge: edge.id, to: try rim(target, z: -5).id, of: target, continuity: .g1)
        }
        #expect(text == closedToOpen)
    }
}

/// A rational B-spline surface periodic in u and clamped in v, evaluated by Cox-de Boor with OCCT's periodic pole convention (the
/// first span uses poles 0 to p), so the seam can be read from either side.
struct PeriodicSheet {
    enum Seam { case start, end }
    let net: BSplineSurface3D
    let sequence: [Double]
    let first: Int
    let uFirst: Double
    let uLast: Double

    init(_ net: BSplineSurface3D) {
        self.net = net
        let period = net.knotsU.last! - net.knotsU[0]
        var seq: [Double] = []
        for cycle in -2...2 {
            for (i, mult) in net.multiplicitiesU.enumerated().dropLast() {
                seq += Array(repeating: net.knotsU[i] + Double(cycle) * period, count: mult)
            }
        }
        sequence = seq
        first = 2 * net.uCount
        uFirst = net.knotsU[0]
        uLast = net.knotsU.last!
    }

    private func basis(_ knots: [Double], _ span: Int, _ t: Double, _ degree: Int) -> [Double] {
        var n = [Double](repeating: 0, count: degree + 1)
        var left = n, right = n
        n[0] = 1
        for j in 1...degree {
            left[j] = t - knots[span + 1 - j]
            right[j] = knots[span + j] - t
            var saved = 0.0
            for r in 0..<j {
                let temp = n[r] / (right[r + 1] + left[j - r])
                n[r] = saved + right[r + 1] * temp
                saved = left[j - r] * temp
            }
            n[j] = saved
        }
        return n
    }

    func point(u: Double, v: Double, seam: Seam) -> Vector3 {
        let n = net.uCount, p = net.degreeU, q = net.degreeV
        let m0 = net.multiplicitiesU[0]
        // The span of u in the extended knots; at the end of the period, the last span of the first cycle.
        var i = first
        if seam == .end, u >= uLast - 1e-12 {
            i = first + n - 1
        } else {
            while i + 1 < first + n, sequence[i + 1] <= u { i += 1 }
        }
        let nu = basis(sequence, i, u, p)
        var flatV: [Double] = []
        for (k, mult) in net.multiplicitiesV.enumerated() { flatV += Array(repeating: net.knotsV[k], count: mult) }
        var j = q
        while j + 1 < net.vCount, flatV[j + 1] <= v { j += 1 }
        let nv = basis(flatV, j, v, q)
        var sum = Vector3(0, 0, 0), weight = 0.0
        for r in 0...p {
            let pole = (((i - p + r) - first - m0 + 1 + p) % n + n) % n
            for s in 0...q {
                let index = pole * net.vCount + (j - q + s)
                let w = (net.weights?[index] ?? 1) * nu[r] * nv[s]
                sum += net.poles[index] * w
                weight += w
            }
        }
        return sum * (1 / weight)
    }
}
#endif
