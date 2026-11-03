import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// How many columns each patch of an end-constrained loft needs, now that every pole row is our own spline along the
/// segment (cubic, quintic where the cubic misses, periodic on a closed loop): the counts are upper bounds, so a change
/// that needs more columns shows here, and they must not move with a last-bit change of a dimension.
extension LoftEndConditionTests {
    /// The columns of a box-top loft to a 12 mm square 10 mm above, at the continuity and weight given.
    func boxLoftColumns(_ continuity: Int32, weight: Double = 1, side: Double = 12) throws -> [Int] {
        let part = try box(20, 20, 10)
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let built = try loft(part, start: end(top, continuity, weight: weight), end: nil, sections: [square(side, at: 20)])
        #expect(isValid(built.shape))
        #expect(built.report.seams_judged == 1)
        return columns(built.report)
    }

    /// The columns of a cylinder-top loft (radius 10) to a circle of `radius` 10 mm above, at Curvature (G2).
    func cylinderLoftColumns(radius: Double = 6) throws -> [Int] {
        let (part, top) = try cylinder()
        let circle = Profile2D.circle(radius: radius, center: Vector2(0, 0), plane: .xy.offset(by: 20))
        let built = try loft(part, start: end(top, 2), end: nil, sections: [circle])
        #expect(isValid(built.shape))
        #expect(built.report.seams_judged == 1)
        return columns(built.report)
    }

    /// The columns of a rounded square's top (20, corners r 3) lofted to a rounded square (12, r 2) at Curvature (G2).
    func roundedLoftColumns(side: Double = 12) throws -> [Int] {
        let part = try OCCTKernel.serialized { try OCCTShape.extrude(rounded(20, 3, at: 0), distance: 10).0 }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let built = try loft(part, start: end(top, 2), end: nil, sections: [rounded(side, 2, at: 20)])
        #expect(isValid(built.shape))
        #expect(built.report.seams_judged == 1)
        return columns(built.report)
    }

    @Test func columnCountsStayWithinTheirBounds() throws {
        let boxG1 = try boxLoftColumns(1), boxG2 = try boxLoftColumns(2)
        let light = try boxLoftColumns(2, weight: 0.1), heavy = try boxLoftColumns(2, weight: 2)
        let circle = try cylinderLoftColumns()
        let lower = try box(20, 20, 10)
        let both = try union(lower, try box(14, 14, 10, centre: Vector2(4, 2), bottom: 30))
        let top = try planarFace(of: both, normal: [0, 0, 1], height: 10)
        let bottom = try planarFace(of: both, normal: [0, 0, -1], height: 30)
        let bridge = try loft(both, start: end(top, 2), end: end(bottom, 2), sections: [])
        #expect(isValid(bridge.shape))
        let roundedColumns = try roundedLoftColumns()
        print("LOFTENDS column bounds: box G1 \(boxG1) G2 \(boxG2) w=0.1 \(light) w=2 \(heavy) circle \(circle)"
            + " bridge \(columns(bridge.report)) rounded \(roundedColumns)")
        // Straight walls: the first five columns (was 9).
        for counts in [boxG1, boxG2, light, heavy, columns(bridge.report)] {
            #expect(counts.count == 4 && counts.allSatisfy { $0 <= 5 }, "\(counts)")
        }
        // A one-edge closed loop: periodic, a knot at every column (was the cap, 129).
        #expect(circle.count == 1 && circle.allSatisfy { $0 <= 17 }, "\(circle)")
        // Smooth vertices between lines and arcs: their shared tangents keep the cubic (unchanged, 45 and 38).
        #expect(roundedColumns.count == 8, "\(roundedColumns)")
        for (k, count) in roundedColumns.enumerated() {
            #expect(count <= (k.isMultiple(of: 2) ? 45 : 38), "segment \(k): \(roundedColumns)")
        }
    }

    /// Last-bit changes to a dimension give the same column counts: the decisions (which spans split, when the skin
    /// turns quintic) are not made by the last bit of the input.
    @Test func columnCountsSurviveLastBitChanges() throws {
        var circles: [[Int]] = [], boxes: [[Int]] = [], roundeds: [[Int]] = []
        for e in [0, 1e-14, -1e-12, 1e-10, 1e-8] {
            circles.append(try cylinderLoftColumns(radius: 6 * (1 + e)))
            boxes.append(try boxLoftColumns(2, side: 12 * (1 + e)))
            roundeds.append(try roundedLoftColumns(side: 12 * (1 + e)))
            print("LOFTENDS last-bit e=\(e): circle \(circles.last ?? []) box \(boxes.last ?? []) rounded \(roundeds.last ?? [])")
        }
        #expect(Set(circles).count == 1, "circle columns differ across last-bit changes: \(circles)")
        #expect(Set(boxes).count == 1, "box columns differ across last-bit changes: \(boxes)")
        #expect(Set(roundeds).count == 1, "rounded columns differ across last-bit changes: \(roundeds)")
    }
}
