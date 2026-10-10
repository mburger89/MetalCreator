import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// S4 decides the S1–S2 handoff's clockwise-arc case: the shim builds an arc with `end < start`
/// clockwise, so a sketch region with a notch (a counter-clockwise loop running along an arc the
/// other way) extrudes. Without it `build_profile` threw "an arc in the profile has no sweep".
struct ClockwiseArcConformanceTests {
    /// The S2 region of a 20 × 10 plate with a semicircular r 4 notch in its top edge, exactly as
    /// `SketchRegions` emits it: counter-clockwise from (0, 0), the notch stored with `end < start`.
    static func notchedPlate(offset: Vector2 = .zero) -> [Segment2D] {
        let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        return loop.map { $0.translated(by: offset) }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aNotchedPlateExtrudesToItsAnalyticVolume(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await kernel.extrude(Profile2D(plane: .xy, segments: Self.notchedPlate()), distance: 3,
                                             mode: .oneSided, tag: tag)
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (200 - 8 * Double.pi)))
        #expect(solid.topology.faces.count == 8)
        let notchWall = try #require(faces(solid, role: .side(segment: 3), of: tag).first)
        #expect(notchWall.kind == .cylinder)
        #expect(isClose(notchWall.area, 3 * 4 * Double.pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleWithANotchIsCut(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let outline = Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments
        let profile = Profile2D(plane: .xy, outer: outline, holes: [Self.notchedPlate(offset: Vector2(-10, -5))])
        let solid = try await kernel.extrude(profile, distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 2 * (1200 - (200 - 8 * Double.pi))))
    }

    /// The notch stays one hole wall of its own loop, named by its segment: the history lookup after the shim reverses the
    /// edge for a clockwise arc finds the hole loop's wall as it does the outer loop's (`aNotchedPlateExtrudesToItsAnalyticVolume`).
    @Test(arguments: KernelUnderTest.allCases)
    func aNotchedHolesWallsAreNamedByTheirLoopAndSegment(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let outline = Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments
        let profile = Profile2D(plane: .xy, outer: outline, holes: [Self.notchedPlate(offset: Vector2(-10, -5))])
        let solid = try await under.make().extrude(profile, distance: 2, mode: .oneSided, tag: tag)
        // Four outer walls, six hole walls, two caps.
        #expect(solid.topology.faces.count == 12)
        for segment in 0..<6 {
            #expect(faces(solid, role: .side(loop: 1, segment: segment), of: tag).count == 1, "hole wall \(segment)")
        }
        let notchWall = try #require(faces(solid, role: .side(loop: 1, segment: 3), of: tag).first)
        #expect(notchWall.kind == .cylinder)
        #expect(isClose(notchWall.area, 2 * 4 * Double.pi))
        #expect(!solid.topology.faces.contains { face in face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aNotchedPlateRevolves(_ under: KernelUnderTest) async throws {
        // Revolved a half turn about the plate's left edge (the y axis): Pappus, area × π × centroid x.
        let kernel = under.make()
        let solid = try await kernel.revolve(Profile2D(plane: .xy, segments: Self.notchedPlate()),
                                             axis: Axis(origin: .zero, direction: .unitY), angle: .degrees(180),
                                             tag: newTag())
        // The plate is symmetric about x = 10, so its centroid x is 10.
        #expect(isClose(try await kernel.properties(of: solid).volume, (200 - 8 * Double.pi) * Double.pi * 10))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aClockwiseArcStillNeedsASweep(_ under: KernelUnderTest) async {
        let dot = Segment2D.arc(center: .zero, radius: 2, start: .degrees(90), end: .degrees(90))
        let loop: [Segment2D] = [dot, .line(dot.endPoint, Vector2(5, 5)), .line(Vector2(5, 5), dot.startPoint)]
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, segments: loop), distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude", reason: "an arc in the profile has no sweep."))
    }
}
