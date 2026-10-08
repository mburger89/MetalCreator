import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct HoleConformanceTests {
    /// A 10 × 10 square on XY centred on the origin with a Ø4 circular hole at (1, 1).
    let plate = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                          holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])

    /// A 4 × 4 square hole centred on the origin, counter-clockwise or clockwise.
    func squareHole(clockwise: Bool) -> [Segment2D] {
        let ccw = Profile2D.rectangle(width: 4, height: 4, plane: .xy).segments
        guard clockwise else { return ccw }
        return ccw.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return .line(b, a)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func extrudingASquareWithACircularHoleIsAnalytic(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(plate, distance: 3, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (100 - Double.pi * 4)))
        #expect(solid.topology.faces.count == 7)
        #expect(solid.topology.faces.filter { $0.kind == .cylinder }.count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases, [false, true])
    func aHoleMayWindEitherWay(_ under: KernelUnderTest, clockwise: Bool) async throws {
        let kernel = under.make()
        let profile = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                                holes: [squareHole(clockwise: clockwise)])
        let solid = try await kernel.extrude(profile, distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 2 * (100 - 16)))
        #expect(solid.topology.faces.count == 10)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aClockwiseOutlineStillCutsItsHole(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return Segment2D.line(b, a)
        }
        let profile = Profile2D(plane: .xy, outer: outline, holes: plate.holes)
        let solid = try await kernel.extrude(profile, distance: 3, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (100 - Double.pi * 4)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func twoHolesAreBothCut(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let holes = [Vector2(-2.5, 0), Vector2(2.5, 0)].map { Profile2D.circle(radius: 1, center: $0, plane: .xy).segments }
        let profile = Profile2D(plane: .xy, outer: plate.outer, holes: holes)
        let solid = try await kernel.extrude(profile, distance: 1, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 100 - 2 * Double.pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aSymmetricExtrudeKeepsTheHole(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(plate, distance: 4, mode: .symmetric, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 4 * (100 - Double.pi * 4)))
        #expect(isClose(solid.bounds.min.z, -2, relative: 1e-4))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleOutsideTheOutlineIsAPlainError(_ under: KernelUnderTest) async {
        let stray = Profile2D(plane: .xy, outer: plate.outer,
                              holes: [Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(stray, distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleCrossingTheOutlineIsAPlainError(_ under: KernelUnderTest) async {
        let crossing = Profile2D(plane: .xy, outer: plate.outer,
                                 holes: [Profile2D.circle(radius: 2, center: Vector2(4, 0), plane: .xy).segments])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(crossing, distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func overlappingHolesAreAPlainError(_ under: KernelUnderTest) async {
        let holes = [Vector2(-0.5, 0), Vector2(0.5, 0)].map { Profile2D.circle(radius: 1, center: $0, plane: .xy).segments }
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: holes), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aZeroAreaHoleIsAPlainError(_ under: KernelUnderTest) async {
        // Closed (out and back), so it passes `isClosed` and reaches the shim's area check.
        let flat: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(0, 0))]
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: [flat]), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude", reason: "a hole in the profile has no area."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func anOpenHoleIsRejected(_ under: KernelUnderTest) async {
        let open: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))]
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: [open]), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
    }

    /// The tube's cross-section on XZ (x 5…15, z 0…10) with a Ø4 hole at x 10, z 5, revolved about Z.
    var tubeSection: Profile2D {
        let plane = Plane(origin: .zero, normal: -.unitY, xAxis: .unitX)
        return Profile2D(plane: plane, outer: Profile2D.polyline([Vector2(5, 0), Vector2(15, 0), Vector2(15, 10), Vector2(5, 10)],
                                                                 closed: true, plane: plane).segments,
                         holes: [Profile2D.circle(radius: 2, center: Vector2(10, 5), plane: plane).segments])
    }

    @Test(arguments: KernelUnderTest.allCases, [360.0, 90.0])
    func revolvingAProfileWithAHoleMakesATubeWithACavity(_ under: KernelUnderTest, degrees: Double) async throws {
        let kernel = under.make()
        let solid = try await kernel.revolve(tubeSection, axis: .z, angle: .degrees(degrees), tag: newTag())
        // Pappus: area (100 − 4π) times the centroid's path (radius 10, both loops centred on x = 10).
        let expected = (100 - 4 * Double.pi) * 10 * degrees * .pi / 180
        #expect(isClose(try await kernel.properties(of: solid).volume, expected, relative: 1e-5))
        #expect(solid.topology.faces.contains { $0.kind == .torus })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aLoftRefusesProfilesWithHoles(_ under: KernelUnderTest) async {
        var top = plate
        top.plane = Plane.xy.offset(by: 5)
        await #expect(throws: KernelError.invalidInput("A loft can't use profiles with holes yet.")) {
            try await under.make().loft([plate, top], ruled: true, tag: newTag())
        }
    }
}
