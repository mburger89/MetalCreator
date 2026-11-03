import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// A loft from a face whose edge has a kink: a degree-5 spline with an interior knot of multiplicity 4 (its second derivative
/// jumps) or 5 (its first does). `segment_breaks` in the shim finds such a knot on the face's edge and breaks the patch's skin
/// there with a column on the break. The profile is extruded and lofted from its top face, so the edge reaches the shim as a
/// B-spline through public kernel calls only.
extension LoftEndConditionTests {
    /// A 16 mm wide, 12 mm deep part: a spline along the bottom with a kink at its middle knot, then three lines.
    func kinkedProfile(multiplicity: Int, at z: Double = 0) -> Profile2D {
        let common: [(Double, Double)] = [(-8, -6), (-6, -7.5), (-3, -5.5), (-1, -8), (1, -7), (3, -9)]
        let tail: [(Double, Double)] = multiplicity == 4
            ? [(5, -6.5), (6, -8), (7, -5.5), (8, -6)]
            : [(4, -6.5), (5, -8.5), (6.5, -5), (7, -7), (8, -6)]
        let poles = (common + tail).map { Vector2($0.0, $0.1) }
        let curve = SplineCurve2D(poles: poles, knots: [0, 0.5, 1], multiplicities: [6, multiplicity, 6])
        precondition(curve.isValid)
        let segments: [Segment2D] = [
            .spline(curve), .line(Vector2(8, -6), Vector2(8, 6)), .line(Vector2(8, 6), Vector2(-8, 6)),
            .line(Vector2(-8, 6), Vector2(-8, -6)),
        ]
        return Profile2D(plane: Plane.xy.offset(by: z), segments: segments)
    }

    /// The section above: the same four segments, smaller, with a smooth spline along the bottom.
    func smoothSection(scale: Double = 1, at z: Double = 20) -> Profile2D {
        let curve = SplineProfileTests.curve([Vector2(-6, -4), Vector2(-2, -5.5), Vector2(2, -5), Vector2(6, -4)])
        let segments: [Segment2D] = [
            .spline(curve), .line(Vector2(6, -4), Vector2(6, 4)), .line(Vector2(6, 4), Vector2(-6, 4)),
            .line(Vector2(-6, 4), Vector2(-6, -4)),
        ]
        return Profile2D(plane: Plane.xy.offset(by: z), segments: segments.map { segment in
            switch segment {
            case .line(let a, let b): .line(a * scale, b * scale)
            case .spline(let spline):
                .spline(SplineCurve2D(poles: spline.poles.map { $0 * scale }, knots: spline.knots, multiplicities: spline.multiplicities))
            default: segment
            }
        })
    }

    func kinkedLoft(multiplicity: Int, _ continuity: Int32, scale: Double = 1) throws -> (part: OCCTShape, built: Built) {
        let part = try OCCTKernel.serialized { try OCCTShape.extrude(kinkedProfile(multiplicity: multiplicity), distance: 10).0 }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let built = try loft(part, start: end(top, continuity), end: nil, sections: [smoothSection(scale: scale)])
        return (part, built)
    }

    @Test(arguments: [4, 5], [Int32(1), Int32(2)])
    func aKinkedEdgeStillJoinsAsPromised(multiplicity: Int, continuity: Int32) throws {
        let (part, built) = try kinkedLoft(multiplicity: multiplicity, continuity)
        #expect(isValid(built.shape))
        #expect(built.report.seams_judged == 1)
        let counts = columns(built.report)
        print("LOFTENDS kink m=\(multiplicity) G\(continuity): columns \(counts)")
        #expect(counts.count == 4 && counts.allSatisfy { $0 <= 17 }, "\(counts)")
        let joined = try union(part, built.shape)
        #expect(isValid(joined))
        let joint = try continuities(of: joined) { abs($0[2] - 10) < 1e-6 }
        #expect(joint.count == 4)
        for found in joint {
            // Tangent promises G1 (a lucky G2 is no failure); Curvature promises G2.
            #expect(continuity == 2 ? found.grade == .g2 : found.grade >= .g1, "\(found)")
        }
    }

    @Test(arguments: [4, 5])
    func kinkedColumnCountsSurviveLastBitChanges(multiplicity: Int) throws {
        var all: [[Int]] = []
        for e in [0, 1e-14, -1e-12, 1e-10, 1e-8] {
            all.append(columns(try kinkedLoft(multiplicity: multiplicity, 2, scale: 1 + e).built.report))
        }
        print("LOFTENDS kink last-bit m=\(multiplicity): \(all)")
        #expect(Set(all).count == 1, "\(all)")
    }
}
