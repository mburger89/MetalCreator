import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Loft ends on curved walls, and smooth vertices of the loft's own sides (final review of G-d).
extension LoftEndConditionTests {
    /// A smooth loft [20 @ 0, 14 @ 10, 18 @ 20]: curved walls meeting at the top face's corners, where each wall's second
    /// derivative differs, so the shared vertex columns must be built once.
    @Test func curvedWallsTopToSmallerSquareIsG1AndG2() throws {
        let part = try OCCTKernel.serialized {
            try OCCTShape.loft([square(20, at: 0), square(14, at: 10), square(18, at: 20)], ruled: false).0
        }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 20)
        for (continuity, grade) in [(Int32(1), ContinuityClass.g1), (Int32(2), ContinuityClass.g2)] {
            let built = try loft(part, start: end(top, continuity), end: nil, sections: [square(10, at: 30)])
            #expect(isValid(built.shape))
            let joined = try union(part, built.shape)
            #expect(isValid(joined))
            let found = try continuities(of: joined) { m in abs(m[2] - 20) < 1e-6 }
            print("LOFTENDS curved walls c=\(continuity): joint \(found.map(\.grade))")
            #expect(found.count == 4)
            #expect(found.allSatisfy { $0.grade == grade })
        }
    }

    /// A rounded rectangle 20 × 20 r3 extruded, lofted from its top to a rounded rectangle 12 × 12 r2 at z = 20 above:
    /// the loft's own vertical edges (where its patches meet) are tangent-continuous where the sections are.
    @Test func roundedRectangleLoftKeepsItsOwnSidesSmooth() throws {
        func rounded(_ side: Double, _ r: Double, at z: Double) -> Profile2D {
            let h = side / 2, c = h - r
            let plane = Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX)
            func corner(_ cx: Double, _ cy: Double, _ a: Double) -> Segment2D {
                .arc(center: Vector2(cx, cy), radius: r, start: Angle(radians: a), end: Angle(radians: a + .pi / 2))
            }
            return Profile2D(plane: plane, segments: [
                .line(Vector2(-c, -h), Vector2(c, -h)), corner(c, -c, -.pi / 2),
                .line(Vector2(h, -c), Vector2(h, c)), corner(c, c, 0),
                .line(Vector2(c, h), Vector2(-c, h)), corner(-c, c, .pi / 2),
                .line(Vector2(-h, c), Vector2(-h, -c)), corner(-c, -c, .pi),
            ])
        }
        let part = try OCCTKernel.serialized { try OCCTShape.extrude(rounded(20, 3, at: 0), distance: 10).0 }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let built = try loft(part, start: end(top, 2), end: nil, sections: [rounded(12, 2, at: 20)])
        #expect(isValid(built.shape))
        let own = try continuities(of: built.shape) { m in m[2] > 10.5 && m[2] < 19.5 }
        print("LOFTENDS rounded own edges: \(own.map(\.grade)) angles \(own.map(\.angleGap))")
        #expect(own.count == 8)
        #expect(own.allSatisfy { $0.grade != .g0 })
        let joined = try union(part, built.shape)
        let joint = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 }
        #expect(joint.count == 8)
        #expect(joint.allSatisfy { $0.grade == .g2 })
    }
}
