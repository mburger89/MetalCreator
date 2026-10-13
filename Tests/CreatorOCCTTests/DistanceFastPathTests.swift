import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The analytic path of `occt_distances` (planes and cylinders with exact formulas) against `BRepExtrema` alone, which the
/// shim keeps callable as `occt_distances_reference`. They must agree to 1e-9 mm everywhere, and most where the formulas
/// change branch: a projection inside a face, outside it near an edge or a hole, on the face, in a hole, round a corner arc.
struct DistanceFastPathTests: DistanceFastPathChecking {
    @Test(arguments: [true, false])
    func thePlatesDistanceMatchesExtremaEverywhere(_ signed: Bool) async throws {
        let shape = try await plate(OCCTKernel())
        // x, y and z at one-millimetre steps (half-millimetre steps take minutes against BRepExtrema): on the faces, on the edges, on the ends of the R4 corner arcs, inside, round it.
        try expectAgreement(shape, grid(x: -36...36, y: -26...26, z: -3...9, step: 1), signed: signed)
    }

    @Test func pointsRoundTheCornerArcsMatchExtrema() async throws {
        let shape = try await plate(OCCTKernel())
        var points: [Vector3] = []
        // A fan of radii and angles round each R4 corner (centres at (±26, ±16)), at heights above, level with and below the plate.
        for (sx, sy) in [(1.0, 1.0), (-1, 1), (1, -1), (-1, -1)] {
            for radius in stride(from: 0.0, through: 9.0, by: 0.37) {
                for degrees in stride(from: -10.0, through: 100.0, by: 3.1) {
                    let angle = degrees * .pi / 180
                    for z in [-2.0, 0, 1.3, 3, 6, 8.5] {
                        points.append(Vector3(sx * (26 + radius * cos(angle)), sy * (16 + radius * sin(angle)), z))
                    }
                }
            }
        }
        try expectAgreement(shape, points, signed: true)
        try expectAgreement(shape, points, signed: false)
    }

    @Test(arguments: [true, false])
    func aPlateWithHolesMatchesExtremaInAndAroundThem(_ signed: Bool) async throws {
        // A round hole and a rectangular one, one near a corner arc, so a planar face has three inner wires.
        let rectangle: [Segment2D] = [
            .line(Vector2(-20, -5), Vector2(-14, -5)), .line(Vector2(-14, -5), Vector2(-14, 4)),
            .line(Vector2(-14, 4), Vector2(-20, 4)), .line(Vector2(-20, 4), Vector2(-20, -5)),
        ]
        let shape = try await plate(OCCTKernel(), holes: [
            circleLoop(at: Vector2(10, 5), radius: 3), rectangle,
            circleLoop(at: Vector2(24, -14), radius: 2),
        ])
        try expectAgreement(shape, grid(x: -36...36, y: -26...26, z: -3...9, step: 1), signed: signed)
        var rings: [Vector3] = []
        // Points in a ring round the round hole's rim, projecting just inside and just outside its edge.
        for degrees in stride(from: 0.0, to: 360.0, by: 7.0) {
            for radius in [0.0, 1.0, 2.9999, 3, 3.0001, 4.5] {
                let angle = degrees * .pi / 180
                for z in [-1.0, 0, 3, 6, 7] {
                    rings.append(Vector3(10 + radius * cos(angle), 5 + radius * sin(angle), z))
                }
            }
        }
        try expectAgreement(shape, rings, signed: signed)
    }

    @Test func aPointInAHoleOrOnAFaceHasTheRightDistance() async throws {
        let shape = try await plate(OCCTKernel(), holes: [circleLoop(at: Vector2(10, 5), radius: 3)])
        // Above the hole's middle, the face below is absent, so the nearest surface is the hole wall: 3 mm away.
        let found = try OCCTKernel.serialized {
            try shape.distances(from: [Vector3(10, 5, 3), Vector3(0, 0, 6), Vector3(0, 0, 0), Vector3(10, 5, 9)][...],
                                kind: .surface, indices: [], signed: false)
        }
        #expect(abs(found[0] - 3) <= tolerance, "in the hole: \(found[0])")
        #expect(abs(found[1]) <= tolerance && abs(found[2]) <= tolerance, "on the top and bottom faces: \(found[1]) \(found[2])")
        #expect(abs(found[3] - hypot(3, 3)) <= tolerance, "above the hole's rim: \(found[3])")
    }

    @Test func aSolidCylinderIncludingItsAxisMatchesExtrema() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.circle(radius: 3, center: Vector2(1, -2), plane: .xy), distance: 10,
                                             mode: .oneSided, tag: newTag())
        let shape = try await kernel.shape(of: solid)
        // The grid hits the axis (x = 1, y = -2) exactly, where a cylinder's nearest point is not unique.
        try expectAgreement(shape, grid(x: -6...8, y: -9...5, z: -3...13, step: 1), signed: true)
        try expectAgreement(shape, grid(x: -6...8, y: -9...5, z: -3...13, step: 1), signed: false)
    }

    @Test func pickedFacesMatchExtremaToo() async throws {
        let shape = try await plate(OCCTKernel())
        let points = grid(x: -36...36, y: -26...26, z: -3...9, step: 1.5)
        for face in 1...10 {
            try expectAgreement(shape, points, kind: .faces, indices: [Int32(face)], signed: false)
        }
        try expectAgreement(shape, points, kind: .faces, indices: [1, 4, 7], signed: false)
    }

    @Test func aMixedSolidWithASphericalFaceStillMatchesExtrema() async throws {
        // A plate unioned with a ball: planar and cylindrical faces take the formulas, the sphere stays on BRepExtrema.
        let kernel = OCCTKernel()
        let base = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6, mode: .oneSided,
                                      tag: newTag())
        let ball = try await kernel.revolve(
            Profile2D(plane: .xz, segments: [
                .arc(center: Vector2(0, 8), radius: 5, start: Angle(radians: -.pi / 2), end: Angle(radians: .pi / 2)),
                .line(Vector2(0, 13), Vector2(0, 3)),
            ]),
            axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: Angle(radians: 2 * .pi), tag: newTag())
        let union = try await kernel.boolean(.union, base, [ball], tag: newTag())
        let shape = try await kernel.shape(of: union)
        try expectAgreement(shape, grid(x: -12...12, y: -12...12, z: -3...16, step: 1), signed: true)
    }
}
