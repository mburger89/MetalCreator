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

    /// A sharp corner folds the pipe's inside over itself, so the sweep is refused (pinned: OCCT's default transition
    /// makes a mitred solid that the self-interference check rejects).
    @Test func anLShapedPathRunsIntoItself() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([.line(.zero, Vector3(0, 0, 20)),
                                               .line(Vector3(0, 0, 20), Vector3(20, 0, 20)),
        ], tag: tag)
        await #expect(throws: KernelError.invalidInput("The sweep runs into itself; shorten the path or shrink the profile.")) {
            _ = try await kernel.sweep([try await circle(kernel)], along: path,
                                       options: SweepOptions(makesSolid: true), tag: tag)
        }
    }

    @Test func aSmoothMultiPieceSolidSweepIsValidAndNamesItsCaps() async throws {
        let kernel = OCCTKernel()
        let path = try await kernel.makeCurve([.line(.zero, Vector3(0, 0, 20)),
                                               .arc(center: Vector3(10, 0, 20), normal: Vector3(0, 1, 0), radius: 10,
                                                    start: Vector3(0, 0, 20), sweep: .pi / 2),
        ], tag: tag)
        let solid = try await kernel.sweep([try await circle(kernel)], along: path,
                                           options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(solid.topology.faces.filter { $0.tags.contains { $0.role == .startCap } }.count == 1)
        #expect(solid.topology.faces.filter { $0.tags.contains { $0.role == .endCap } }.count == 1)
        let volume = try await kernel.properties(of: solid).volume
        #expect(relative(volume, .pi * 4 * (20 + .pi / 2 * 10)) < 1e-4)
    }

    @Test func twoProfilesBlendAlongThePath() async throws {
        let kernel = OCCTKernel()
        let path = try await line(kernel, to: Vector3(0, 0, 50))
        let solid = try await kernel.sweep([try await circle(kernel), try await circle(kernel, radius: 4, z: 50)],
                                           along: path, options: SweepOptions(makesSolid: true), tag: tag)
        #expect(solid.isClosed)
        #expect(solid.topology.faces.contains { $0.tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))) })
        #expect(solid.topology.faces.contains { $0.tags.contains { $0.role == .startCap } })
        let frustum = Double.pi * 50 / 3 * (4 + 8 + 16)
        #expect(relative(try await kernel.properties(of: solid).volume, frustum) < 1e-3)
    }
}
#endif
