#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-G Task 4: Blend Surface on closed edges (R6), two tube rims; the fixtures are `BlendSurfaceTests`'s.
extension BlendSurfaceTests {
    /// The tube of radius `radius` about z, z from `from` to `to`, its seam at `start` degrees, revolved the other way when `reversed`.
    func tube(radius: Double, from: Double, to: Double, start: Double = 0, reversed: Bool = false) async throws -> Solid {
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

    /// The blend of the rim of a tube (radius 10, z 0...20) at z = 20 to the rim of a tube (radius 14, z 30...50) at z = 30.
    func blendedTubes(_ continuity: PatchContinuity, start: Double = 0, reversed: Bool = false) async throws -> (Solid, Solid, Solid) {
        let lower = try await tube(radius: 10, from: 0, to: 20)
        let upper = try await tube(radius: 14, from: 30, to: 50, start: start, reversed: reversed)
        let result = try await blend(lower, try rim(lower, z: 20).id, upper, try rim(upper, z: 30).id, continuity)
        return (lower, upper, result)
    }

    /// The result is one periodic face whose rims lie on the two rims and are its only roles, graded as asked at both, with no twist.
    func checkTubes(_ lower: Solid, _ upper: Solid, _ result: Solid, _ continuity: PatchContinuity) async throws {
        #expect(result.topology.faces.count == 1)
        let net = try await kernel.controlNet(of: result).surface
        #expect(net.isPeriodicU && !net.isPeriodicV)
        let sheet = PeriodicSheet(net)
        let rims = [(v: 0.0, solid: lower, z: 20.0, radius: 10.0), (v: 1.0, solid: upper, z: 30.0, radius: 14.0)]
        for end in rims {
            let target = try rim(end.solid, z: end.z)
            for i in 0..<64 {
                let u = sheet.uFirst + (sheet.uLast - sheet.uFirst) * Double(i) / 64
                let gap = try await kernel.shortestDistance(between: .point(sheet.point(u: u, v: end.v)),
                                                            and: .edge(end.solid, target.id)).distance
                #expect(gap <= 1e-4, "v \(end.v) u \(u) gap \(gap)")
            }
        }
        // The seam is closed: the same point from both sides, and no kink across it (a second difference is O(h^2) when it is smooth).
        let h = 1e-4, span = sheet.uLast - sheet.uFirst
        for v in [0.0, 0.5, 1.0] {
            let at = sheet.point(u: sheet.uFirst, v: v)
            #expect((sheet.point(u: sheet.uLast, v: v) - at).length < 1e-7, "v \(v)")
            let kink = sheet.point(u: sheet.uFirst + h * span, v: v) - at * 2 + sheet.point(u: sheet.uLast - h * span, v: v)
            #expect(kink.length < 1e-4, "v \(v) kink \(kink.length)")
        }
        let wanted: ContinuityClass = continuity == .g2 ? .g2 : .g1
        let atA = try await kernel.continuity(of: try edge(result, .start).id, in: result, against: FaceID(0), of: lower)
        let atB = try await kernel.continuity(of: try edge(result, .end).id, in: result, against: FaceID(0), of: upper)
        #expect(atA.grade >= wanted && atB.grade >= wanted,
                "A \(atA.angleGap) \(atA.curvatureGap) B \(atB.angleGap) \(atB.curvatureGap)")
        #expect(atA.positionGap <= 1e-4 && atB.positionGap <= 1e-4)
        // No twist: each u-iso runs from the first rim to within 1 mm of the nearest point of the second.
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let u = sheet.uFirst + fraction * span
            let from = sheet.point(u: u, v: 0)
            let angle = atan2(from.y, from.x)
            let nearest = Vector3(14 * cos(angle), 14 * sin(angle), 30)
            let end = sheet.point(u: u, v: 1)
            #expect((end - nearest).length < 1, "u \(u) lands \(end), nearest \(nearest)")
        }
        // The roles are the two rims; the seam is none.
        func roles(_ role: BoundaryRole) -> [EdgeInfo] {
            result.topology.edges.filter { $0.tags.contains(TopoTag(tag, .boundary(role))) }
        }
        #expect(roles(.start).count == 1 && roles(.end).count == 1)
        #expect(roles(.start).allSatisfy { abs($0.midpoint.z - 20) < 1e-6 } && roles(.end).allSatisfy { abs($0.midpoint.z - 30) < 1e-6 })
        #expect(roles(.rail(0)).isEmpty && roles(.rail(1)).isEmpty)
        let tagged = result.topology.edges.filter { edge in
            edge.tags.contains { if case .boundary = $0.role { true } else { false } }
        }
        #expect(tagged.count == 2, "only the rims carry a role, not the seam")
    }

    @Test(arguments: [PatchContinuity.g1, .g2])
    func twoTubeRimsBlend(continuity: PatchContinuity) async throws {
        let (lower, upper, result) = try await blendedTubes(continuity)
        try await checkTubes(lower, upper, result, continuity)
    }

    @Test func offsetSeamsDoNotTwist() async throws {
        let (lower, upper, result) = try await blendedTubes(.g1, start: 90)
        try await checkTubes(lower, upper, result, .g1)
    }

    @Test func aReversedRimDoesNotTwist() async throws {
        let (lower, upper, result) = try await blendedTubes(.g1, reversed: true)
        try await checkTubes(lower, upper, result, .g1)
    }

    @Test func aClosedAndAnOpenEdgeRefuse() async throws {
        let sheet = try await a()
        let lower = try await tube(radius: 10, from: 0, to: 20)
        let sentence = "Blend Surface needs both edges closed, or both open."
        let rim = try rim(lower, z: 20).id
        let open = try edge(sheet, .end).id
        let closedFirst = await refusal { _ = try await blend(lower, rim, sheet, open) }
        #expect(closedFirst == sentence)
        let openFirst = await refusal { _ = try await blend(sheet, open, lower, rim) }
        #expect(openFirst == sentence)
    }
}
#endif
