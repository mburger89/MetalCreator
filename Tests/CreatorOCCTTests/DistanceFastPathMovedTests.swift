import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The fast path on shapes that were moved: by `Kernel.transform` (geometry baked in, so a shared corner's two edges compute it
/// from different curves), by `Kernel.place` (a pattern copy) and by a `TopLoc_Location` (a STEP import's way). The moves are
/// 90° and 180° turns with translations that doubles cannot hold (0.1, 0.3), so corners land a unit in the last place apart; the
/// points sit at the corner levels, one and two units either side, in the planes of the faces.
struct DistanceFastPathMovedTests: DistanceFastPathChecking {
    /// The local points to move: every vertex level of the plate (x = ±30, ±26; y = ±20, ±16) with a few between and beyond,
    /// in the planes of the faces and either side of them.
    var localPoints: [Vector3] {
        var points: [Vector3] = []
        for x in [-34.0, -30, -26, -20, -16, -10, 0, 10, 16, 20, 26, 30, 34] {
            for y in [-24.0, -20, -16, -8, 0, 8, 16, 20, 24] {
                for z in [-1.0, 0, 3, 6, 7] { points.append(Vector3(x, y, z)) }
            }
        }
        return points
    }

    func plateSolid(_ kernel: OCCTKernel, holes: [[Segment2D]] = []) async throws -> Solid {
        var profile = Profile2D.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy)
        profile.holes = holes
        return try await kernel.extrude(profile, distance: 6, mode: .oneSided, tag: newTag())
    }

    func check(_ shape: OCCTShape, moving map: (Vector3) -> Vector3) throws {
        let points = localPoints.flatMap { nudged(map($0)) }
        try expectAgreement(shape, points, signed: true)
        try expectAgreement(shape, points, signed: false)
    }

    /// 90° about Z, then (0.1, 0.3, 0): local (x, y, z) goes to (-y + 0.1, x + 0.3, z).
    func turnedQuarter(_ point: Vector3) -> Vector3 { Vector3(-point.y + 0.1, point.x + 0.3, point.z) }

    /// 180° about X, then (0.7, -0.1, 6.1): local (x, y, z) goes to (x + 0.7, -y - 0.1, -z + 6.1).
    func turnedHalf(_ point: Vector3) -> Vector3 { Vector3(point.x + 0.7, -point.y - 0.1, -point.z + 6.1) }

    let quarterTurn = Transform(translation: Vector3(0.1, 0.3, 0), rotationAxis: Axis(origin: .zero, direction: .unitZ),
                                rotation: .degrees(90))
    let halfTurn = Transform(translation: Vector3(0.7, -0.1, 6.1), rotationAxis: Axis(origin: .zero, direction: .unitX),
                             rotation: .degrees(180))

    @Test func aPlateMovedByTransformMatchesExtrema() async throws {
        let kernel = OCCTKernel()
        let moved = try await kernel.transform(try await plateSolid(kernel), by: quarterTurn, tag: newTag())
        try check(try await kernel.shape(of: moved), moving: turnedQuarter)
    }

    @Test func aPlateWithHolesMovedByTransformMatchesExtrema() async throws {
        let kernel = OCCTKernel()
        let holes = [circleLoop(at: Vector2(10, 5), radius: 3), circleLoop(at: Vector2(-14, -6), radius: 2.5)]
        let moved = try await kernel.transform(try await plateSolid(kernel, holes: holes), by: quarterTurn, tag: newTag())
        try check(try await kernel.shape(of: moved), moving: turnedQuarter)
    }

    @Test func patternCopiesMadeByPlaceMatchExtrema() async throws {
        let kernel = OCCTKernel()
        let plate = try await plateSolid(kernel)
        let copies = try await kernel.place([plate, plate], at: [quarterTurn, halfTurn], qualifying: { $0 }, tag: newTag())
        try check(try await kernel.shape(of: copies[0]), moving: turnedQuarter)
        try check(try await kernel.shape(of: copies[1]), moving: turnedHalf)
    }

    @Test func aShapeWithALocationMatchesExtrema() async throws {
        let kernel = OCCTKernel()
        let plate = try await kernel.shape(of: try await plateSolid(kernel, holes: [circleLoop(at: Vector2(10, 5), radius: 3)]))
        let angle = Angle.degrees(90).radians
        let located = try OCCTKernel.serialized { () throws -> OCCTShape in
            try plate.locatedCopy(translation: Vector3(0.1, 0.3, 0), rotationAboutZ: angle)
        }
        try check(located, moving: turnedQuarter)
        // A located copy of an already moved shape composes the two locations.
        let twice = try OCCTKernel.serialized { () throws -> OCCTShape in
            try located.locatedCopy(translation: Vector3(0.7, -0.1, 0), rotationAboutZ: angle)
        }
        try check(twice, moving: { point in
            let once = turnedQuarter(point)
            return Vector3(-once.y + 0.7, once.x - 0.1, once.z)
        })
    }
}
