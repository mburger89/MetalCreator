#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// An end-condition loft to a section with a spline segment: the section end lies on the spline, the solid is valid and the
/// joint grades as promised.
struct LoftEndSplineTests {
    let kernel = OCCTKernel()

    func part() async throws -> (Solid, FaceID) {
        let solid = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: newTag())
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && $0.normal == Vector3(0, 0, 1) })
        return (solid, top.id)
    }

    /// Four segments like the box's top face: a spline along the bottom bulging outwards, then three lines.
    func splineSection(at z: Double = 20) -> (Profile2D, SplineCurve2D) {
        let curve = SplineProfileTests.curve([Vector2(-8, -6), Vector2(-3, -8), Vector2(3, -7.5), Vector2(8, -6)])
        let segments: [Segment2D] = [
            .spline(curve), .line(Vector2(8, -6), Vector2(8, 6)), .line(Vector2(8, 6), Vector2(-8, 6)),
            .line(Vector2(-8, 6), Vector2(-8, -6)),
        ]
        return (Profile2D(plane: Plane.xy.offset(by: z), segments: segments), curve)
    }

    @Test(arguments: [LoftContinuity.tangent, .curvature])
    func theSectionEndLiesOnTheSpline(_ continuity: LoftContinuity) async throws {
        let (part, top) = try await part()
        let (section, curve) = splineSection()
        let tag = newTag()
        let built = try await kernel.loft([section], ruled: false, part: part, start: LoftEnd(face: top, continuity: continuity),
                                          end: nil, tag: tag)
        let range = curve.parameterRange
        let samples = (0..<100).map { k -> Vector3 in
            let p = curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double(k) / 99)
            return Vector3(p.x, p.y, 20)
        }
        let found = try await kernel.distances(from: samples, to: .solid(built), signed: false)
        #expect((found.max() ?? 1) < 1e-3, "\(found.max() ?? -1)")
        let cap = try #require(faces(built, role: .endCap, of: tag).first)
        let expected = SplineProfileTests.area(section.segments)
        #expect(abs(cap.area - expected) / expected < 1e-4, "\(cap.area) vs \(expected)")
        #expect(try await kernel.properties(of: built).volume > 0)

        let joined = try await kernel.boolean(.union, part, [built], tag: newTag())
        let joint = joined.topology.edges.filter { edge in
            abs(edge.midpoint.z - 10) < 1e-6 && abs(max(abs(edge.midpoint.x), abs(edge.midpoint.y)) - 10) < 1e-6
        }
        #expect(joint.count == 4)
    }

    @Test(arguments: [LoftContinuity.tangent, .curvature])
    func theJointGradesAsPromised(_ continuity: LoftContinuity) async throws {
        let (part, top) = try await part()
        let (section, _) = splineSection()
        let built = try await kernel.loft([section], ruled: false, part: part, start: LoftEnd(face: top, continuity: continuity),
                                          end: nil, tag: newTag())
        let joined = try await kernel.boolean(.union, part, [built], tag: newTag())
        let joint = joined.topology.edges.filter { edge in
            abs(edge.midpoint.z - 10) < 1e-6 && abs(max(abs(edge.midpoint.x), abs(edge.midpoint.y)) - 10) < 1e-6
        }
        for edge in joint {
            let grade = try await kernel.continuity(along: edge.id, of: joined).grade
            #expect(grade == (continuity == .curvature ? .g2 : .g1) || grade == .g2)
        }
    }

    @Test func aFreeFaceEndWithASplineSectionIsValid() async throws {
        let (part, top) = try await part()
        let (section, curve) = splineSection()
        let built = try await kernel.loft([section], ruled: false, part: part, start: LoftEnd(face: top, continuity: .free),
                                          end: nil, tag: newTag())
        let range = curve.parameterRange
        let samples = (0..<50).map { k -> Vector3 in
            let p = curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double(k) / 49)
            return Vector3(p.x, p.y, 20)
        }
        let found = try await kernel.distances(from: samples, to: .solid(built), signed: false)
        #expect((found.max() ?? 1) < 1e-3)
    }
}
#endif
