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
            let p = sheet.point(u: u, v: 3)
            #expect(abs(hypot(p.x, p.y) - 10) < 1e-9 && abs(p.z - 3) < 1e-9, "u \(u) \(p)")
        }
        // The rational arcs' ends are at 120 degree steps: a whole-arc shift of the poles would show here.
        for (i, knot) in net.knotsU.dropLast().enumerated() {
            let p = sheet.point(u: knot, v: 0)
            let angle = 2 * Double.pi * Double(i) / 3
            #expect(abs(p.x - 10 * cos(angle)) < 1e-9 && abs(p.y - 10 * sin(angle)) < 1e-9, "knot \(knot) \(p)")
        }
    }

    /// The result, matched to a closed rim: its rim lies on the target, it grades as asked, it is periodic along the rim (the seam is
    /// then OCCT's own periodic wrap), and no ruling is twisted (each lands within 1 mm of the point nearest its own start).
    func check(_ result: Solid, from source: Solid, target: Solid, targetRim: EdgeInfo, continuity: PatchContinuity) async throws {
        let sourceNet = try await kernel.controlNet(of: source).surface
        let before = PeriodicSheet(sourceNet)
        let net = try await kernel.controlNet(of: result).surface
        #expect(net.isPeriodicU, "the result stays periodic along the rim")
        let sheet = PeriodicSheet(net)
        for i in 0..<64 {
            let u = 2 * Double.pi * Double(i) / 64
            let gap = try await kernel.shortestDistance(between: .point(sheet.point(u: u, v: 0)),
                                                        and: .edge(target, targetRim.id)).distance
            #expect(gap <= 1e-4, "u \(u) gap \(gap)")
        }
        let found = try await kernel.continuity(of: try matchedRim(result).id, in: result, against: FaceID(0), of: target)
        let wanted: ContinuityClass = continuity == .g2 ? .g2 : continuity == .g1 ? .g1 : .g0
        #expect(found.grade >= wanted, "angle \(found.angleGap) curvature \(found.curvatureGap)")
        #expect(found.positionGap <= 1e-4)
        // No twist.
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let u = sheet.uFirst + fraction * (sheet.uLast - sheet.uFirst)
            let was = before.point(u: u, v: 0)
            let angle = atan2(was.y, was.x)
            let nearest = Vector3(12 * cos(angle), 12 * sin(angle), -5)
            let end = sheet.point(u: u, v: 0)
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

    @Test func aFarSeamAndAReversedTargetDoNotTwist() async throws {
        let source = try await tube()
        let target = try await tube(radius: 12, from: -5, to: -25, start: 137, reversed: true)
        let result = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: try rim(target, z: -5).id, of: target,
                                              continuity: .g2)
        try await check(result, from: source, target: target, targetRim: try rim(target, z: -5), continuity: .g2)
    }

    /// A Loft Surface through two closed rings: a clamped closed surface that is not periodic. `smooth` rings are the exact rational
    /// circle (degree 2, nine poles, a clamped seam); the others are an octagon's cubic with a corner at the seam.
    func loftedTube(smooth: Bool, radius: Double = 10, from: Double = 0, to: Double = 20) async throws -> Solid {
        func ring(_ radius: Double, z: Double) async throws -> Curve {
            if smooth {
                let w = 0.5.squareRoot()
                let r = radius
                let poles = [Vector3(r, 0, z), Vector3(r, r, z), Vector3(0, r, z), Vector3(-r, r, z), Vector3(-r, 0, z),
                             Vector3(-r, -r, z), Vector3(0, -r, z), Vector3(r, -r, z), Vector3(r, 0, z),
                ]
                return try await kernel.makeCurve([
                .spline(BSplineCurve3D(
                    degree: 2, poles: poles, weights: [1, w, 1, w, 1, w, 1, w, 1], knots: [0, 0.25, 0.5, 0.75, 1],
                    multiplicities: [3, 2, 2, 2, 3])),
                ], tag: tag)
            }
            var poles = (0..<8).map { k -> Vector3 in
                let a = 2 * Double.pi * Double(k) / 8
                return Vector3(radius * cos(a), radius * sin(a), z)
            }
            poles.append(poles[0])
            return try await kernel.makeCurve([
                .spline(BSplineCurve3D(
                degree: 3, poles: poles, knots: [0, 1, 2, 3, 4, 5, 6], multiplicities: [4, 1, 1, 1, 1, 1, 4])),
            ], tag: tag)
        }
        let tube = try await kernel.loftSurface([ring(radius, z: from), ring(radius, z: to)], ruled: false, closed: false, tag: tag)
        let net = try await kernel.controlNet(of: tube).surface
        #expect(!net.isPeriodicU && !net.isPeriodicV, "the fixture is closed but not periodic")
        return tube
    }

    @Test func aClampedClosedLoftIsMadePeriodicAndMatched() async throws {
        let source = try await loftedTube(smooth: true)
        let target = try await tube(radius: 12, from: -5, to: -25, reversed: true)
        let rimEdge = try rim(source, z: 0)
        #expect(source.topology.edges.filter { $0.faces.count == 1 }.count == 2)
        let result = try await kernel.matched(source, edge: rimEdge.id, to: try rim(target, z: -5).id, of: target, continuity: .g2)
        let net = try await kernel.controlNet(of: result).surface
        #expect(net.isPeriodicU, "the result is periodic along the rim")
        let found = try await kernel.continuity(of: try matchedRim(result).id, in: result, against: FaceID(0), of: target)
        #expect(found.grade >= .g2, "angle \(found.angleGap) curvature \(found.curvatureGap)")
        #expect(found.positionGap <= 1e-4)
        // No twist: each rim point lands within 1 mm of the target point nearest where it started.
        let before = PeriodicSheet(try await kernel.controlNet(of: source).surface)
        let after = PeriodicSheet(net)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let was = before.point(u: before.uFirst + fraction * (before.uLast - before.uFirst), v: 0)
            let now = after.point(u: after.uFirst + fraction * (after.uLast - after.uFirst), v: 0)
            let angle = atan2(was.y, was.x)
            #expect((now - Vector3(12 * cos(angle), 12 * sin(angle), -5)).length < 1, "fraction \(fraction) lands \(now)")
        }
    }

    @Test func aClosedLoftWithACornerRefuses() async throws {
        let source = try await loftedTube(smooth: false)
        let target = try await tube(radius: 12, from: -5, to: -25)
        let text = await refusal {
            _ = try await kernel.matched(source, edge: try rim(source, z: 0).id, to: try rim(target, z: -5).id, of: target,
                                         continuity: .g1)
        }
        #expect(text == "Match Surface can't match a closed edge of a surface that doesn't close smoothly.")
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

/// A (rational) B-spline surface periodic or clamped in u and clamped in v, evaluated by Cox-de Boor; a periodic u follows
/// OCCT's pole convention (the first span uses poles 0 to p).
struct PeriodicSheet {
    let net: BSplineSurface3D
    let sequence: [Double]
    let first: Int
    let uFirst: Double
    let uLast: Double

    init(_ net: BSplineSurface3D) {
        self.net = net
        uFirst = net.knotsU[0]
        uLast = net.knotsU.last!
        var seq: [Double] = []
        if net.isPeriodicU {
            let period = uLast - uFirst
            for cycle in -2...2 {
                for (i, mult) in net.multiplicitiesU.enumerated().dropLast() {
                    seq += Array(repeating: net.knotsU[i] + Double(cycle) * period, count: mult)
                }
            }
            first = 2 * net.uCount
        } else {
            for (i, mult) in net.multiplicitiesU.enumerated() { seq += Array(repeating: net.knotsU[i], count: mult) }
            first = net.degreeU
        }
        sequence = seq
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

    func point(u: Double, v: Double) -> Vector3 {
        let n = net.uCount, p = net.degreeU, q = net.degreeV
        let m0 = net.multiplicitiesU[0]
        var i = first
        let spans = net.isPeriodicU ? n : net.uCount - p
        while i + 1 < first + spans, sequence[i + 1] <= u { i += 1 }
        let nu = basis(sequence, i, u, p)
        var flatV: [Double] = []
        for (k, mult) in net.multiplicitiesV.enumerated() { flatV += Array(repeating: net.knotsV[k], count: mult) }
        var j = q
        while j + 1 < net.vCount, flatV[j + 1] <= v { j += 1 }
        let nv = basis(flatV, j, v, q)
        var sum = Vector3(0, 0, 0), weight = 0.0
        for r in 0...p {
            let pole = net.isPeriodicU ? (((i - p + r) - first - m0 + 1 + p) % n + n) % n : i - p + r
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
