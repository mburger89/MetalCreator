import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelHoleTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
    let circle = Profile2D.circle(radius: 2, center: .zero, plane: .xy).segments
    let square = Profile2D.rectangle(width: 4, height: 4, plane: .xy).segments

    func roles(_ solid: Solid) -> [TopoRole] { solid.topology.faces.flatMap(\.tags).map(\.role) }

    @Test func holeWallsAreTaggedWithTheirLoop() async throws {
        let solid = try await FakeKernel().extrude(Profile2D(plane: .xy, outer: outline, holes: [circle, square]), distance: 2,
                                                   mode: .oneSided, tag: tag)
        // Two caps, four outer walls, one circular hole wall, four square hole walls.
        #expect(solid.topology.faces.count == 11)
        #expect(roles(solid).filter { $0 == .side(loop: 1, segment: 0) }.count == 1)
        for k in 0..<4 {
            #expect(roles(solid).filter { $0 == .side(segment: k) }.count == 1)
            #expect(roles(solid).filter { $0 == .side(loop: 2, segment: k) }.count == 1)
        }
    }

    @Test func theOuterLoopIsNumberedAsWithoutHoles() async throws {
        let kernel = FakeKernel()
        let plain = try await kernel.extrude(Profile2D(plane: .xy, segments: outline), distance: 2, mode: .oneSided, tag: tag)
        let holed = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [square]), distance: 2,
                                             mode: .oneSided, tag: tag)
        #expect(Array(holed.topology.faces.prefix(plain.topology.faces.count)) == plain.topology.faces)
        #expect(Array(holed.topology.edges.prefix(plain.topology.edges.count)) == plain.topology.edges)
        #expect(holed.bounds == plain.bounds)
    }

    @Test func aCircularHoleHasASeamAndASquareHoleHasConcaveCorners() async throws {
        let kernel = FakeKernel()
        let round = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [circle]), distance: 2,
                                             mode: .oneSided, tag: tag)
        #expect(round.topology.edges.filter(\.isSeam).count == 1)
        let squared = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [square]), distance: 2,
                                               mode: .oneSided, tag: tag)
        #expect(squared.topology.edges.filter { $0.convexity == .concave }.count == 4)
        #expect(squared.topology.edges.allSatisfy { squared.topology.key(of: $0) != nil })
    }

    @Test func anOpenHoleIsRejected() async {
        let open: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0))]
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await FakeKernel().extrude(Profile2D(plane: .xy, outer: outline, holes: [open]), distance: 1, mode: .oneSided, tag: tag)
        }
    }

    @Test func aLoftRefusesProfilesWithHoles() async {
        let holed = Profile2D(plane: .xy, outer: outline, holes: [circle])
        await #expect(throws: KernelError.invalidInput("A loft can't use profiles with holes yet.")) {
            try await FakeKernel().loft([holed, holed], ruled: true, tag: tag)
        }
    }

    /// The OCCT kernel's message (HoleConformanceTests): the stand-in must fail the same way, or a graph test passes on it
    /// that fails for a person.
    static let strayHole = KernelError.operationFailed(
        operation: "extrude", reason: "a hole in the profile is outside the outline or overlaps another loop.")

    @Test func aHoleOutsideTheOutlineIsRefused() async {
        let stray = Profile2D(plane: .xy, outer: outline, holes: [Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments])
        await #expect(throws: Self.strayHole) {
            try await FakeKernel().extrude(stray, distance: 1, mode: .oneSided, tag: tag)
        }
    }

    @Test func aHoleCrossingTheOutlineIsRefused() async {
        let crossing = Profile2D(plane: .xy, outer: outline,
                                 holes: [Profile2D.circle(radius: 2, center: Vector2(4, 0), plane: .xy).segments])
        await #expect(throws: Self.strayHole) {
            try await FakeKernel().extrude(crossing, distance: 1, mode: .oneSided, tag: tag)
        }
    }

    @Test func aHoleInsideTheOutlineStillExtrudes() async throws {
        let inside = Profile2D(plane: .xy, outer: outline, holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])
        let solid = try await FakeKernel().extrude(inside, distance: 1, mode: .oneSided, tag: tag)
        #expect(solid.bounds.size.x == 10)
    }
}
