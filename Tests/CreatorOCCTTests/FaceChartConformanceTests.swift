import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// `Kernel.faceParametrization` and `Kernel.faceCoordinates` on OpenCascade (implicit spec §3.5, Face mapping): a cylinder's side, a
/// fillet, the rim, and the refusals. The cylinder is 10 mm in radius and 20 mm tall on the Z axis from z = 0.
struct FaceChartConformanceTests {
    func cylinder(_ kernel: OCCTKernel) async throws -> Solid {
        let profile = Profile2D(plane: .xz, segments: [
            .line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 20)),
            .line(Vector2(10, 20), Vector2(0, 20)), .line(Vector2(0, 20), Vector2(0, 0)),
        ])
        return try await kernel.revolve(profile, axis: .z, angle: Angle(radians: 2 * .pi), tag: newTag())
    }

    func side(_ solid: Solid) throws -> FaceInfo {
        try #require(solid.topology.faces.first { $0.kind == .cylinder })
    }

    @Test func aCylindersSideIsAnAngleAroundItsRadiusAndAHeight() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let facts = try await kernel.faceParametrization(of: try side(solid).id, in: solid)
        #expect(facts.kind == .cylinder && !facts.hasDegenerateEdge)
        #expect(abs(try #require(facts.uPeriod) - 2 * Double.pi) < 1e-9 && facts.vPeriod == nil, "it closes on itself round the axis")
        #expect(abs(facts.uScale - 10) < 1e-9 && abs(facts.vScale - 1) < 1e-9, "u is an angle of radius 10, v is a height")
        #expect(abs(facts.uMid - Double.pi) < 1e-9 && abs(facts.vMid - 10) < 1e-9)
    }

    @Test func pointsAreAtTheirAngleHeightAndDepth() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let face = try side(solid).id
        func at(_ radius: Double, _ degrees: Double, _ z: Double) -> Vector3 {
            Vector3(radius * cos(degrees * .pi / 180), radius * sin(degrees * .pi / 180), z)
        }
        let found = try await kernel.faceCoordinates(of: [at(10, 90, 5), at(7, 200, 12), at(14, 300, 19)], on: face, in: solid)
        let expected = [(90.0, 5.0, 0.0), (200, 12, -3), (300, 19, 4)]
        for (sample, want) in zip(found, expected) {
            let angle = want.0 * .pi / 180
            #expect(abs(sample.u - angle) < 1e-9 && abs(sample.v - want.1) < 1e-9 && abs(sample.depth - want.2) < 1e-9,
                    "\(sample) against \(want)")
        }
    }

    @Test func pastTheRimTheNearestPointIsOnTheRimAndTheDepthIsAlongTheNormal() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let face = try side(solid).id
        // Above the top cap, 5 mm in from the side: the nearest point of the side is the top rim, at the same angle.
        let found = try await kernel.faceCoordinates(of: [Vector3(0, 5, 26)], on: face, in: solid)
        let sample = try #require(found.first)
        #expect(abs(sample.u - Double.pi / 2) < 1e-9 && abs(sample.v - 20) < 1e-9)
        #expect(abs(sample.depth + 5) < 1e-9, "5 mm inside the surface across the normal there")
    }

    @Test func aFilletIsAPartialSurfaceWithNoPeriod() async throws {
        let kernel = OCCTKernel()
        let block = try await box(kernel, 40, 40, 10)
        let edge = try #require(block.topology.edges.first { $0.kind == .line && isClose($0.length, 10) })
        let rounded = try await kernel.fillet(block, edges: [edge.id], radius: 4, tag: newTag())
        let blend = try #require(rounded.topology.faces.first { $0.kind == .cylinder })
        let facts = try await kernel.faceParametrization(of: blend.id, in: rounded)
        #expect(facts.uPeriod == nil && facts.vPeriod == nil)
        #expect(abs(facts.uScale - 4) < 1e-6 || abs(facts.vScale - 4) < 1e-6, "the arc direction scales by the fillet radius")
        // The block's corner at (±20, ±20) is rounded about an axis 4 mm in from both sides: the axis is 4 mm inside the surface, and the
        // old corner is 4 (√2 − 1) outside it.
        let corner = Vector3(edge.midpoint.x, edge.midpoint.y, 5)
        let axis = Vector3(corner.x - 4 * corner.x.sign.sgn, corner.y - 4 * corner.y.sign.sgn, 5)
        let found = try await kernel.faceCoordinates(of: [axis, corner], on: blend.id, in: rounded)
        #expect(abs(found[0].depth + 4) < 1e-9 && abs(found[1].depth - 4 * (2.0.squareRoot() - 1)) < 1e-9, "\(found)")
        #expect(abs(found[0].v - found[1].v) < 1e-9, "the same height along the axis")
    }

    @Test func aMissingFaceAForeignSolidAndACancelledTaskAreRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        await #expect(throws: KernelError.invalidInput("The face doesn't exist on the solid.")) {
            _ = try await kernel.faceCoordinates(of: [.zero], on: FaceID(99), in: solid)
        }
        await #expect(throws: KernelError.invalidInput("A point to project is not a finite position.")) {
            _ = try await kernel.faceCoordinates(of: [Vector3(.nan, 0, 0)], on: try side(solid).id, in: solid)
        }
        let fake = FakeKernel()
        let foreign = try await fake.extrude(.rectangle(width: 4, height: 4, plane: .xy), distance: 4, mode: .oneSided, tag: newTag())
        await #expect(throws: KernelError.invalidInput("This solid was made by a different kernel.")) {
            _ = try await kernel.faceParametrization(of: FaceID(0), in: foreign)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.faceCoordinates(of: [.zero], on: try side(solid).id, in: solid)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func aBatchOfManyPointsIsAnsweredInOrder() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let points = (0..<5_000).map { index -> Vector3 in
            let angle = Double(index) * 0.01 + 0.1
            return Vector3(9 * cos(angle), 9 * sin(angle), Double(index % 20))
        }
        let found = try await kernel.faceCoordinates(of: points, on: try side(solid).id, in: solid)
        #expect(found.count == points.count)
        for index in [0, 2_047, 2_048, 4_999] {
            let angle = (Double(index) * 0.01 + 0.1).truncatingRemainder(dividingBy: 2 * Double.pi)
            #expect(abs(found[index].depth + 1) < 1e-9 && abs(found[index].u - angle) < 1e-9, "point \(index)")
        }
    }
}

private extension FloatingPointSign {
    /// 1 for plus, -1 for minus.
    var sgn: Double { self == .plus ? 1 : -1 }
}
