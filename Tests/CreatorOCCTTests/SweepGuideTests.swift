#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 Task 7: a sweep with a second rail, a guide surface and twist.
struct SweepGuideTests {
    let tag = newTag()

    func rectangle(_ kernel: OCCTKernel) async throws -> Curve {
        let corners = [Vector3(-5, -2, 0), Vector3(5, -2, 0), Vector3(5, 2, 0), Vector3(-5, 2, 0)]
        return try await kernel.makeCurve((0..<4).map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
    }

    func line(_ kernel: OCCTKernel, _ from: Vector3, _ to: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(from, to)], tag: tag)
    }

    /// An open V from the origin to (10, 0, 0) in the XY plane: not collinear, so it has a plane to turn in.
    func vee(_ kernel: OCCTKernel) async throws -> Curve {
        try await kernel.makeCurve([.line(.zero, Vector3(5, 3, 0)), .line(Vector3(5, 3, 0), Vector3(10, 0, 0))], tag: tag)
    }

    /// The direction across the face tagged `role`: between the midpoints of its two longest edges, which a twisted sweep
    /// leaves as B-splines with no direction of their own. It is square to the longest edges' direction.
    func acrossLongEdges(_ solid: Solid, of role: TopoRole) throws -> Vector3 {
        let face = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == role } })
        let edges = solid.topology.edges.filter { $0.faces.contains(face.id) }.sorted { $0.length > $1.length }
        try #require(edges.count >= 2)
        return try #require((edges[0].midpoint - edges[1].midpoint).normalized)
    }

    @Test func aNinetyDegreeTwistTurnsTheEndProfile() async throws {
        let kernel = OCCTKernel()
        let path = try await line(kernel, .zero, Vector3(0, 0, 50))
        let solid = try await kernel.sweep([try await rectangle(kernel)], along: path,
                                           options: SweepOptions(makesSolid: true, twist: 90), tag: tag)
        #expect(solid.isClosed && !solid.hasOpenShell)
        let start = try acrossLongEdges(solid, of: .startCap)
        let end = try acrossLongEdges(solid, of: .endCap)
        let degrees = acos(min(1, abs(start.dot(end)))) * 180 / .pi
        #expect(abs(degrees - 90) < 0.01, "the end profile is turned \(degrees) degrees")
    }

    @Test func aTwoRailSweepStaysOnBothRails() async throws {
        let kernel = OCCTKernel()
        let profile = try await vee(kernel)
        let path = try await line(kernel, .zero, Vector3(0, 0, 50))
        let rail = try await line(kernel, Vector3(10, 0, 0), Vector3(20, 0, 50))
        let solid = try await kernel.sweep([profile], along: path, options: SweepOptions(orientation: .secondRail),
                                           guide: .rail(rail), tag: tag)
        let edge = try #require(solid.topology.edges.first { $0.tags.contains { $0.role == .boundary(.rail(1)) } })
        // The point of the rail's line nearest the edge's midpoint.
        let origin = Vector3(10, 0, 0)
        let along = Vector3(10, 0, 50)
        let offset = edge.midpoint - origin
        let t = offset.dot(along) / along.dot(along)
        let nearest = origin + along * t
        #expect((edge.midpoint - nearest).length < 1e-4, "the rail edge strays \((edge.midpoint - nearest).length) mm")
        #expect(abs(solid.bounds.max.x - 20) < 1e-4)
    }

    @Test func aGuideSurfaceKeepsTheProfileNormal() async throws {
        let kernel = OCCTKernel()
        let cylinder = try await kernel.extrude(try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi),
        ], tag: tag), direction: .unitZ, distance: 50, symmetric: true, tag: tag)
        let path = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2),
        ], tag: tag)
        let profile = try await kernel.makeCurve([
            .arc(center: Vector3(10, 0, 0), normal: Vector3(0, 1, 0), radius: 1, start: Vector3(11, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let solid = try await kernel.sweep([profile], along: path,
                                           options: SweepOptions(orientation: .guideSurface, makesSolid: true),
                                           guide: .surface(cylinder), tag: tag)
        #expect(solid.isClosed)
        #expect(try await kernel.properties(of: solid).volume > 0)
    }

    @Test func twistWithARailIsRefused() async throws {
        let kernel = OCCTKernel()
        let rail = try await line(kernel, Vector3(10, 0, 0), Vector3(20, 0, 50))
        await #expect(throws: KernelError.invalidInput("Twist can't be combined with a rail or a guide surface.")) {
            _ = try await kernel.sweep([try await vee(kernel)],
                                       along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                       options: SweepOptions(orientation: .secondRail, twist: 30), guide: .rail(rail), tag: tag)
        }
    }

    @Test func aRailThatMissesIsRefused() async throws {
        let kernel = OCCTKernel()
        let rail = try await line(kernel, Vector3(12, 0, 0), Vector3(20, 0, 50))
        await #expect(throws: KernelError.invalidInput("The rail must touch every profile.")) {
            _ = try await kernel.sweep([try await vee(kernel)],
                                       along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                       options: SweepOptions(orientation: .secondRail), guide: .rail(rail), tag: tag)
        }
    }

    @Test func aStraightLineProfileCannotFollowARail() async throws {
        let kernel = OCCTKernel()
        let rail = try await line(kernel, Vector3(10, 0, 0), Vector3(20, 0, 50))
        await #expect(throws: KernelError.invalidInput("A rail sweep needs profiles that aren't straight lines.")) {
            _ = try await kernel.sweep([try await line(kernel, .zero, Vector3(10, 0, 0))],
                                       along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                       options: SweepOptions(orientation: .secondRail), guide: .rail(rail), tag: tag)
        }
    }

    // MARK: Straight profiles and rails

    func railSweep(_ profile: Curve, _ kernel: OCCTKernel) async throws -> Solid {
        let rail = try await line(kernel, Vector3(10, 0, 0), Vector3(20, 0, 50))
        return try await kernel.sweep([profile], along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                      options: SweepOptions(orientation: .secondRail), guide: .rail(rail), tag: tag)
    }

    @Test func twoCollinearLinesAsAProfileAreRefused() async throws {
        let kernel = OCCTKernel()
        let profile = try await kernel.makeCurve([.line(.zero, Vector3(4, 0, 0)), .line(Vector3(4, 0, 0), Vector3(10, 0, 0))], tag: tag)
        await #expect(throws: KernelError.invalidInput("A rail sweep needs profiles that aren't straight lines.")) {
            _ = try await railSweep(profile, kernel)
        }
    }

    /// A 10 mm chord bowed by 0.001 mm (a tenth of a thousandth of its length).
    func nearlyStraightArc(_ kernel: OCCTKernel, sagitta: Double) async throws -> Curve {
        let radius = 100 / (8 * sagitta) + sagitta / 2
        let sweep = 2 * asin(5 / radius)
        return try await kernel.makeCurve([
            .arc(center: Vector3(5, -(radius - sagitta), 0), normal: Vector3(0, 0, -1), radius: radius,
                 start: .zero, sweep: sweep),
        ], tag: tag)
    }

    @Test func aNearlyStraightArcIsRefusedWithARail() async throws {
        let kernel = OCCTKernel()
        let profile = try await nearlyStraightArc(kernel, sagitta: 1e-3)
        await #expect(throws: KernelError.invalidInput("A rail sweep needs profiles that aren't straight lines.")) {
            _ = try await railSweep(profile, kernel)
        }
    }

    @Test func aStraightProfileIsRefusedWithAGuideSurface() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.extrude(try await line(kernel, Vector3(10, 0, 0), Vector3(20, 0, 0)),
                                             direction: .unitZ, distance: 50, symmetric: false, tag: tag)
        await #expect(throws: KernelError.invalidInput("A guide sweep needs profiles that aren't straight lines.")) {
            _ = try await kernel.sweep([try await line(kernel, .zero, Vector3(10, 0, 0))],
                                       along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                       options: SweepOptions(orientation: .guideSurface), guide: .surface(sheet), tag: tag)
        }
    }

    // MARK: Twist on curved paths

    func quarterArc(_ kernel: OCCTKernel) async throws -> Curve {
        try await kernel.makeCurve([.arc(center: .zero, normal: .unitZ, radius: 30, start: Vector3(30, 0, 0), sweep: .pi / 2)], tag: tag)
    }

    /// Left through 60 degrees, then right through 60 degrees: an S that ends heading +X again, 30 mm radius each.
    func sCurve(_ kernel: OCCTKernel) async throws -> Curve {
        let join = Vector3(30 * sin(.pi / 3), 30 - 30 * cos(.pi / 3), 0)
        let center = Vector3(2 * join.x, 0, 0)
        return try await kernel.makeCurve([
            .arc(center: Vector3(0, 30, 0), normal: .unitZ, radius: 30, start: .zero, sweep: .pi / 3),
            .arc(center: center, normal: Vector3(0, 0, -1), radius: 30, start: join, sweep: .pi / 3),
        ], tag: tag)
    }

    /// A profile standing across the path's start: for the arc, which starts at (30, 0, 0) heading +Y, a rectangle in XZ.
    func profileAcross(_ kernel: OCCTKernel, at origin: Vector3, tangent: Vector3) async throws -> Curve {
        // Long side (10) along the world Z, short side (4) across the path's plane.
        let across = tangent.cross(.unitZ).normalized ?? .unitX
        let corners = [origin + across * -2 + Vector3(0, 0, -5), origin + across * 2 + Vector3(0, 0, -5),
                       origin + across * 2 + Vector3(0, 0, 5), origin + across * -2 + Vector3(0, 0, 5),
        ]
        return try await kernel.makeCurve((0..<4).map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
    }

    @Test func aNinetyDegreeTwistAlongAQuarterArcTurnsTheEndByNinety() async throws {
        let kernel = OCCTKernel()
        let path = try await quarterArc(kernel)
        let profile = try await profileAcross(kernel, at: Vector3(30, 0, 0), tangent: .unitY)
        let plain = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true), tag: tag)
        let twisted = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true, twist: 90), tag: tag)
        #expect(twisted.isClosed && !twisted.hasOpenShell)
        // The start cap keeps the profile as given: its long edges run along Z.
        let startLong = try #require(twisted.topology.faces.first { $0.tags.contains { $0.role == .startCap } })
        let longest = twisted.topology.edges.filter { $0.faces.contains(startLong.id) }.max { $0.length < $1.length }
        #expect(try #require(longest).length > 9.99)
        // Against the untwisted sweep the end profile is turned by the twist: compare cap directions.
        let before = try acrossLongEdges(plain, of: .endCap)
        let after = try acrossLongEdges(twisted, of: .endCap)
        let degrees = acos(min(1, abs(before.dot(after)))) * 180 / .pi
        #expect(abs(degrees - 90) < 0.01, "the end profile is turned \(degrees) degrees")
    }

    @Test func aNinetyDegreeTwistAlongAnSCurveTurnsTheEndByNinety() async throws {
        let kernel = OCCTKernel()
        let path = try await sCurve(kernel)
        let profile = try await profileAcross(kernel, at: .zero, tangent: .unitX)
        let plain = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true), tag: tag)
        let twisted = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true, twist: 90), tag: tag)
        let before = try acrossLongEdges(plain, of: .endCap)
        let after = try acrossLongEdges(twisted, of: .endCap)
        let degrees = acos(min(1, abs(before.dot(after)))) * 180 / .pi
        #expect(abs(degrees - 90) < 0.01, "the end profile is turned \(degrees) degrees")
        let startBefore = try acrossLongEdges(plain, of: .startCap)
        let startAfter = try acrossLongEdges(twisted, of: .startCap)
        #expect(abs(startBefore.dot(startAfter)) > 0.9999)
    }

    @Test func aPathThatBendsTooTightlyToTwistAlongIsRefused() async throws {
        let kernel = OCCTKernel()
        // A 0.001 mm radius arc: half its radius is under the 0.001 mm the offset needs.
        let path = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 0.001, start: Vector3(0.001, 0, 0), sweep: .pi),
        ], tag: tag)
        await #expect(throws: KernelError.invalidInput("The path bends too tightly to twist along.")) {
            _ = try await kernel.sweep([try await rectangle(kernel)], along: path,
                                       options: SweepOptions(makesSolid: true, twist: 30), tag: tag)
        }
    }

    @Test func aTwistBeyondTheLimitIsRefused() async throws {
        let kernel = OCCTKernel()
        await #expect(throws: KernelError.invalidInput("The twist must be between \u{2212}3,600\u{00B0} and 3,600\u{00B0}.")) {
            _ = try await kernel.sweep([try await rectangle(kernel)], along: try await line(kernel, .zero, Vector3(0, 0, 50)),
                                       options: SweepOptions(makesSolid: true, twist: 4000), tag: tag)
        }
    }
}
#endif
