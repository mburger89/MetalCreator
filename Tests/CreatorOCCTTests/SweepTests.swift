#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-1 Task 5: sweeping profile curves along a path.
struct SweepTests {
    let tag = newTag()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func line(_ kernel: OCCTKernel, to end: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(.zero, end)], tag: tag)
    }

    /// A circle about +Z at the origin.
    func circle(_ kernel: OCCTKernel, radius: Double = 2, z: Double = 0) async throws -> Curve {
        try await kernel.makeCurve([
            .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: radius, start: Vector3(radius, 0, z), sweep: 2 * .pi),
        ], tag: tag)
    }

    /// A quarter arc of `radius` that leaves the origin along +Z, turning towards +X.
    func quarterArc(_ kernel: OCCTKernel, radius: Double) async throws -> Curve {
        try await kernel.makeCurve([
            .arc(center: Vector3(radius, 0, 0), normal: Vector3(0, 1, 0), radius: radius,
                 start: .zero, sweep: .pi / 2),
        ], tag: tag)
    }

    func count(_ solid: Solid, _ role: BoundaryRole) -> Int {
        solid.topology.edges.filter { $0.tags.contains { $0.role == .boundary(role) } }.count
    }

    func relative(_ a: Double, _ b: Double) -> Double { abs(a - b) / abs(b) }

    @Test func aCircleAlongALineIsACylinder() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.sweep([try await circle(kernel)], along: try await line(kernel, to: Vector3(0, 0, 50)),
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        let volume = try await kernel.properties(of: solid).volume
        #expect(relative(volume, .pi * 4 * 50) < 1e-6)
        #expect(solid.topology.faces.contains { $0.tags.contains { $0.role == .startCap } })
        #expect(solid.topology.faces.contains { $0.tags.contains { $0.role == .endCap } })
        #expect(solid.topology.faces.contains { $0.tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))) })
    }

    @Test func aCircleAlongAQuarterArcFollowsPappus() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.sweep([try await circle(kernel)], along: try await quarterArc(kernel, radius: 30),
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        let volume = try await kernel.properties(of: solid).volume
        #expect(relative(volume, .pi * 4 * (.pi / 2 * 30)) < 1e-4)
    }

    @Test func anOpenArcProfileGivesANamedSheet() async throws {
        let kernel = OCCTKernel()
        let profile = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2),
        ], tag: tag)
        let sheet = try await kernel.sweep([profile], along: try await line(kernel, to: Vector3(0, 0, 50)),
                                           options: SweepOptions(), tag: tag)
        #expect(!sheet.isClosed)
        #expect(sheet.topology.faces.count == 1)
        #expect(sheet.topology.faces[0].tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))))
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        #expect(count(sheet, .rail(0)) == 1 && count(sheet, .rail(1)) == 1)
        #expect(relative(try await kernel.properties(of: sheet).surfaceArea, Double.pi * 50) < 1e-6)
        let rail0 = try #require(sheet.topology.edges.first { $0.tags.contains { $0.role == .boundary(.rail(0)) } })
        #expect(abs(rail0.midpoint.x - 2) < 1e-6 && abs(rail0.midpoint.y) < 1e-6)
        let end = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }
        #expect(end.allSatisfy { abs($0.midpoint.z - 50) < 1e-6 })
    }

    @Test func aClosedProfileWithoutMakesSolidIsATube() async throws {
        let kernel = OCCTKernel()
        let tube = try await kernel.sweep([try await circle(kernel)], along: try await line(kernel, to: Vector3(0, 0, 50)),
                                          options: SweepOptions(), tag: tag)
        #expect(!tube.isClosed)
        #expect(count(tube, .start) == 1 && count(tube, .end) == 1)
    }

    @Test func anEndScaleOfTwoGivesAFrustum() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.sweep([try await circle(kernel)], along: try await line(kernel, to: Vector3(0, 0, 50)),
                                           options: SweepOptions(endScale: 2, makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        // r from 2 to 4 over 50 mm.
        let frustum = Double.pi * 50 / 3 * (4 + 8 + 16)
        #expect(relative(try await kernel.properties(of: solid).volume, frustum) < 1e-4)
    }

    @Test func anEndScaleWithTwoProfilesIsRefused() async throws {
        let kernel = OCCTKernel()
        let path = try await line(kernel, to: Vector3(0, 0, 50))
        await #expect(throws: KernelError.invalidInput("An end scale needs exactly one profile.")) {
            _ = try await kernel.sweep([try await circle(kernel), try await circle(kernel, z: 25)], along: path,
                                       options: SweepOptions(endScale: 2), tag: tag)
        }
    }

    @Test func profilesWithDifferentPieceCountsAreRefused() async throws {
        let kernel = OCCTKernel()
        let path = try await line(kernel, to: Vector3(0, 0, 50))
        let two = try await kernel.makeCurve([.line(Vector3(0, 0, 25), Vector3(2, 0, 25)),
                                              .line(Vector3(2, 0, 25), Vector3(2, 2, 25)),
        ], tag: tag)
        let one = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(2, 0, 0))], tag: tag)
        await #expect(throws: KernelError.invalidInput("Sweep profiles need the same number of pieces.")) {
            _ = try await kernel.sweep([one, two], along: path, options: SweepOptions(), tag: tag)
        }
    }

    @Test func frenetFollowsAHelix() async throws {
        let kernel = OCCTKernel()
        let points = (0...36).map { i -> Vector3 in
            let t = Double(i) * .pi / 12
            return Vector3(10 * cos(t), 10 * sin(t), 2 * t)
        }
        let tangent = Vector3(0, 10, 2)
        let path = try await kernel.interpolate(points, degree: 3, closed: false, startTangent: tangent,
                                                endTangent: nil, tag: tag)
        let unit = try #require(tangent.normalized)
        let profile = try await kernel.makeCurve([
            .arc(center: Vector3(10, 0, 0), normal: unit, radius: 1, start: Vector3(11, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let solid = try await kernel.sweep([profile], along: path,
                                           options: SweepOptions(orientation: .frenet, makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(try await kernel.properties(of: solid).volume > 0)
    }

    @Test func aFixedBinormalFollowsAPlanarSCurve() async throws {
        let kernel = OCCTKernel()
        let points = [Vector3(0, 0, 0), Vector3(10, 5, 0), Vector3(20, 0, 0), Vector3(30, -5, 0), Vector3(40, 0, 0)]
        let path = try await kernel.interpolate(points, degree: 3, closed: false, startTangent: Vector3(1, 0, 0),
                                                endTangent: nil, tag: tag)
        let profile = try await kernel.makeCurve([
            .arc(center: .zero, normal: Vector3(1, 0, 0), radius: 1, start: Vector3(0, 1, 0), sweep: 2 * .pi),
        ], tag: tag)
        let solid = try await kernel.sweep([profile], along: path,
                                           options: SweepOptions(orientation: .fixedBinormal, binormal: .unitZ,
                                                                 makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(try await kernel.properties(of: solid).volume > 0)
    }

    @Test func aProfileWiderThanTheBendRunsIntoItself() async throws {
        let kernel = OCCTKernel()
        await #expect(throws: KernelError.invalidInput("The sweep runs into itself; shorten the path or shrink the profile.")) {
            _ = try await kernel.sweep([try await circle(kernel, radius: 10)], along: try await quarterArc(kernel, radius: 5),
                                       options: SweepOptions(makesSolid: true), tag: tag)
        }
    }

    /// The corner is rounded, so the sweep is valid. Its volume is the two legs' cylinders (2 * pi * 4 * 20), less the
    /// inside of the corner where the legs fold over each other (at most the bicylinder 16 r^3 / 3 = 42.7), plus the
    /// outside of the corner, a quarter of a sphere of the profile's radius (8.4).
    @Test func anLShapedPathBuildsWithARoundCorner() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([
            .line(.zero, Vector3(0, 0, 20)),
            .line(Vector3(0, 0, 20), Vector3(20, 0, 20)),
        ], tag: tag)
        let solid = try await kernel.sweep([try await circle(kernel)], along: path,
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        let legs = 2 * Double.pi * 4 * 20
        let volume = try await kernel.properties(of: solid).volume
        #expect(volume > legs - 16 * 8 / 3.0)
        #expect(volume < legs + 4.0 / 3 * .pi * 8 / 4)
        // Two legs and the corner between them are three spans, each its own name.
        let sides = solid.topology.faces.filter { $0.tags.contains { if case .side = $0.role { true } else { false } } }
        #expect(sides.count == 3)
        #expect(Set(sides.map(\.tags)).count == 3)
    }

    @Test func aSolidAlongALineAndAnArcNamesEachSpan() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([
            .line(.zero, Vector3(0, 0, 20)),
            .arc(center: Vector3(10, 0, 20), normal: Vector3(0, 1, 0), radius: 10, start: Vector3(0, 0, 20), sweep: .pi / 2),
        ], tag: tag)
        let solid = try await kernel.sweep([try await circle(kernel)], along: path,
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.topology.faces.count == 4)
        #expect(Set(solid.topology.faces.map(\.tags)).count == 4)
        let span0 = try #require(solid.topology.faces.first { $0.tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))) })
        let span1 = try #require(solid.topology.faces.first { $0.tags.contains(TopoTag(tag, .side(loop: 1, segment: 0))) })
        #expect(relative(span0.area, 2 * .pi * 2 * 20) < 1e-6)
        #expect(relative(span1.area, 2 * .pi * 2 * (.pi / 2 * 10)) < 1e-4)
    }

    @Test func twoProfilesMakeOneSpanAndTheTagsAreDistinct() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.sweep([try await circle(kernel), try await circle(kernel, radius: 4, z: 50)],
                                           along: try await line(kernel, to: Vector3(0, 0, 50)),
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.topology.faces.count == 3)
        #expect(Set(solid.topology.faces.map(\.tags)).count == 3)
    }

    @Test func aClosedPathMakesATorusWithNoCaps() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 20, start: Vector3(20, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let profile = try await kernel.makeCurve([
            .arc(center: Vector3(20, 0, 0), normal: Vector3(0, 1, 0), radius: 3, start: Vector3(23, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let solid = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(relative(try await kernel.properties(of: solid).volume, 2 * .pi * .pi * 20 * 9) < 1e-4)
        #expect(!solid.topology.faces.contains { $0.tags.contains { $0.role == .startCap || $0.role == .endCap } })
    }

    @Test func aNearlyClosedPathKeepsItsCaps() async throws {
        let kernel = OCCTKernel()
        let sweep = 350 * Double.pi / 180
        let path = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 20, start: Vector3(20, 0, 0), sweep: sweep),
        ], tag: tag)
        let profile = try await kernel.makeCurve([
            .arc(center: Vector3(20, 0, 0), normal: Vector3(0, 1, 0), radius: 3, start: Vector3(23, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let solid = try await kernel.sweep([profile], along: path, options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(relative(try await kernel.properties(of: solid).volume, .pi * 9 * 20 * sweep) < 1e-4)
        let start = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .startCap } })
        let end = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .endCap } })
        #expect((start.centroid - Vector3(20, 0, 0)).length < 1e-6)
        #expect((end.centroid - Vector3(20 * cos(sweep), 20 * sin(sweep), 0)).length < 1e-6)
    }

    @Test func railsFollowEachSpanOfThePath() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([
            .line(.zero, Vector3(0, 0, 20)),
            .arc(center: Vector3(10, 0, 20), normal: Vector3(0, 1, 0), radius: 10, start: Vector3(0, 0, 20), sweep: .pi / 2),
        ], tag: tag)
        let profile = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2),
        ], tag: tag)
        let sheet = try await kernel.sweep([profile], along: path, options: SweepOptions(), tag: tag)
        #expect(sheet.topology.faces.count == 2)
        #expect(count(sheet, .rail(0)) == 2 && count(sheet, .rail(1)) == 2)
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        // Rail 0 starts at the profile's first point (2,0,0), rail 1 at its last (0,2,0).
        let first = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.rail(0)) } }
        let second = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.rail(1)) } }
        #expect(first.allSatisfy { $0.midpoint.y.magnitude < 1e-6 })
        #expect(second.allSatisfy { $0.midpoint.y > 1 })
    }

    @Test func anEndScaleOnAnArcQuadruplesTheEndArea() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.sweep([try await circle(kernel)], along: try await quarterArc(kernel, radius: 30),
                                           options: SweepOptions(endScale: 2, makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        let start = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .startCap } })
        let end = try #require(solid.topology.faces.first { $0.tags.contains { $0.role == .endCap } })
        #expect(relative(end.area, 4 * start.area) < 1e-4)
    }
}
#endif
