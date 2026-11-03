import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2 of G-d: loft end conditions through `OCCTKernel` (tags, the join, the refusals in words).
struct LoftEndKernelTests {
    let kernel = OCCTKernel()

    /// A 20 × 20 × 10 box and its top face.
    func part() async throws -> (Solid, FaceID) {
        let solid = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: newTag())
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && $0.normal == Vector3(0, 0, 1) })
        return (solid, top.id)
    }

    func section(_ side: Double = 12, at z: Double = 20) -> Profile2D {
        .rectangle(width: side, height: side, plane: Plane.xy.offset(by: z))
    }

    func loft(
        _ sections: [Profile2D], ruled: Bool = false, part: Solid?, start: LoftEnd? = nil, end: LoftEnd? = nil, tag: NodeTag = newTag()
    ) async throws -> Solid {
        try await kernel.loft(sections, ruled: ruled, part: part, start: start, end: end, tag: tag)
    }

    /// The loft's side k is the face edge paired with profile segment k: with the section's segments rotated, tag k still
    /// lands on the face next to that segment, whatever order the face's own wire runs in.
    @Test func sideTagsFollowTheFaceLoop() async throws {
        let (part, top) = try await part()
        let plain = Profile2D.rectangle(width: 12, height: 8, plane: Plane.xy.offset(by: 20))
        for shift in 0..<4 {
            let rotated = Array(plain.segments.dropFirst(shift) + plain.segments.prefix(shift))
            let profile = Profile2D(plane: plain.plane, segments: rotated)
            let tag = newTag()
            let start = LoftEnd(face: top, continuity: .curvature)
            let built = try await loft([profile], part: part, start: start, tag: tag)
            #expect(faces(built, role: .startCap, of: tag).count == 1)
            #expect(faces(built, role: .endCap, of: tag).count == 1)
            #expect(built.topology.faces.count == 6)
            for k in 0..<4 {
                let side = try #require(faces(built, role: .side(segment: k), of: tag).first)
                let middle = (rotated[k].startPoint + rotated[k].endPoint) * 0.5
                // The side lies the way its profile segment does from the centre (the same axis, the same sign).
                #expect(side.centroid.x * middle.x + side.centroid.y * middle.y > 0)
                #expect(abs(side.centroid.x * middle.y - side.centroid.y * middle.x) < 1e-6)
            }
            // None of the part's tags pass through.
            let partTags = Set(part.topology.faces.flatMap(\.tags))
            #expect(built.topology.faces.allSatisfy { $0.tags.isDisjoint(with: partTags) })
        }
    }

    @Test func aLoftFromAFaceJoinsG2() async throws {
        let (part, top) = try await part()
        let start = LoftEnd(face: top, continuity: .curvature, weight: 1.5)
        let built = try await loft([section()], part: part, start: start)
        let joined = try await kernel.boolean(.union, part, [built], tag: newTag())
        let joint = joined.topology.edges.filter { edge in
            abs(edge.midpoint.z - 10) < 1e-6 && abs(max(abs(edge.midpoint.x), abs(edge.midpoint.y)) - 10) < 1e-6
        }
        #expect(joint.count == 4)
        for edge in joint {
            #expect(try await kernel.continuity(along: edge.id, of: joined).grade == .g2)
        }
    }

    @Test func aBridgeNeedsNoProfile() async throws {
        let lower = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: newTag())
        let upperProfile = Profile2D.rectangle(width: 14, height: 14, plane: Plane.xy.offset(by: 30))
        let upper = try await kernel.extrude(upperProfile, distance: 10, mode: .oneSided, tag: newTag())
        let both = try await kernel.boolean(.union, lower, [upper], tag: newTag())
        let top = try #require(both.topology.faces.first { $0.normal == Vector3(0, 0, 1) && abs($0.centroid.z - 10) < 1e-9 })
        let bottom = try #require(both.topology.faces.first {
            $0.normal == Vector3(0, 0, -1) && abs($0.centroid.z - 30) < 1e-9
        })
        let tag = newTag()
        let start = LoftEnd(face: top.id, continuity: .curvature)
        let end = LoftEnd(face: bottom.id, continuity: .tangent)
        let bridge = try await loft([], part: both, start: start, end: end, tag: tag)
        #expect(faces(bridge, role: .startCap, of: tag).count == 1)
        #expect(faces(bridge, role: .endCap, of: tag).count == 1)
        #expect(try await kernel.properties(of: bridge).volume > 0)
    }

    @Test func aFreeFaceEndBuildsLikeThruSections() async throws {
        let (part, top) = try await part()
        let tag = newTag()
        let free = try await loft([section()], part: part, start: LoftEnd(face: top, continuity: .free), tag: tag)
        let base = Profile2D.rectangle(width: 20, height: 20, plane: Plane.xy.offset(by: 10))
        let plain = try await kernel.loft([base, section()], ruled: false, tag: newTag())
        let volumes = try await (kernel.properties(of: free).volume, kernel.properties(of: plain).volume)
        #expect(isClose(volumes.0, volumes.1, relative: 1e-9))
        for k in 0..<4 {
            #expect(faces(free, role: .side(segment: k), of: tag).count == 1)
        }
    }

    @Test func refusalsAreWorded() async throws {
        let (part, top) = try await part()
        let tangent = LoftEnd(face: top, continuity: .tangent)
        await #expect(throws: KernelError.invalidInput("Straight sides can't have end conditions.")) {
            try await loft([section()], ruled: true, part: part, start: tangent)
        }
        await #expect(throws: KernelError.invalidInput("Pick a face of the part for the loft's end.")) {
            try await loft([section()], part: nil, end: tangent)
        }
        await #expect(throws: KernelError.weightNotPositive) {
            try await loft([section()], part: part, start: LoftEnd(face: top, continuity: .tangent, weight: 0))
        }
        await #expect(throws: KernelError.loftWeightTooLarge) {
            try await loft([section()], part: part, start: LoftEnd(face: top, continuity: .curvature, weight: 40))
        }
        await #expect(throws: KernelError.invalidInput("Every loft section needs the same number of segments.")) {
            try await loft([.circle(radius: 5, center: .zero, plane: Plane.xy.offset(by: 20))], part: part, start: tangent)
        }
        await #expect(throws: KernelError.loftFaceVanished) {
            try await loft([section()], part: part, start: LoftEnd(face: FaceID(99), continuity: .tangent))
        }
    }

    /// A curved face (the cylinder's wall) can't be a section.
    @Test func aCurvedFaceIsRefused() async throws {
        let disc = Profile2D.circle(radius: 10, center: .zero, plane: .xy)
        let cylinder = try await kernel.extrude(disc, distance: 10, mode: .oneSided, tag: newTag())
        let wall = try #require(cylinder.topology.faces.first { $0.kind != .plane })
        await #expect(throws: KernelError.loftEndFaceNotFlat) {
            try await loft([section()], part: cylinder, start: LoftEnd(face: wall.id, continuity: .tangent))
        }
    }
}
