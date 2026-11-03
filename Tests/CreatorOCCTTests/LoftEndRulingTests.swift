import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2 of G-d: the shim's rulings (a circle starts nearest the section, columns are added where a span fails, a weight that
/// loops a column back and a curved end face are refused).
extension LoftEndConditionTests {
    // MARK: Rulings

    /// The cylinder of radius 10 and height 10 and its top face.
    func cylinder() throws -> (OCCTShape, Int) {
        let part = try OCCTKernel.serialized {
            try OCCTShape.extrude(.circle(radius: 10, center: Vector2(0, 0), plane: .xy), distance: 10).0
        }
        return (part, try planarFace(of: part, normal: [0, 0, 1], height: 10))
    }

    /// A circle whose start point is at 90 degrees (its x axis is the world's y).
    func quarterTurnedCircle(radius: Double, at z: Double) -> Profile2D {
        let plane = Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitY)
        return .circle(radius: radius, center: Vector2(0, 0), plane: plane)
    }

    /// The middle of the loft's one seam edge (the column the circle's start runs along).
    func seamMidpoint(of shape: OCCTShape) throws -> [Double] {
        let seams = topology(of: shape).edges.filter { $0.faceA == $0.faceB && $0.faceA > 0 }
        return try #require(seams.first).midpoint
    }

    /// A circle section started a quarter turn from the face edge's own start: the column from the section's start runs
    /// to the nearest point of the face's circle (0, 10), not to the edge's vertex (10, 0), so the loft doesn't twist.
    @Test func circleStartsAtThePointNearestTheSection() throws {
        let (part, top) = try cylinder()
        let circle = quarterTurnedCircle(radius: 6, at: 20)
        let built = try loft(part, start: end(top, 2), end: nil, sections: [circle])
        print("LOFTENDS circle start: columns \(columns(built.report))")
        #expect(isValid(built.shape))
        let mid = try seamMidpoint(of: built.shape)
        #expect(abs(mid[0]) < 1e-6)
        #expect(mid[1] > 6)
        let joined = try union(part, built.shape)
        #expect(isValid(joined))
        let found = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 }
        #expect(!found.isEmpty && found.allSatisfy { $0.grade == .g2 })
    }

    /// The same without a condition (OCCT's ThruSections through a circle started where the section starts).
    @Test func freeCircleStartsAtThePointNearestTheSection() throws {
        let (part, top) = try cylinder()
        let built = try loft(part, start: end(top, 0), end: nil, sections: [quarterTurnedCircle(radius: 6, at: 20)])
        #expect(isValid(built.shape))
        let mid = try seamMidpoint(of: built.shape)
        #expect(abs(mid[0]) < 1e-6)
        #expect(mid[1] > 6)
    }

    /// Columns are added where a span fails, not everywhere: each case's counts are printed for the record.
    @Test func columnCountsAreAdaptive() throws {
        let (part, top) = try cylinder()
        let small = Profile2D.circle(radius: 6, center: Vector2(0, 0), plane: .xy.offset(by: 20))
        let cylinderLoft = try loft(part, start: end(top, 2), end: nil, sections: [small])
        let box = try self.box(20, 20, 10)
        let boxTop = try planarFace(of: box, normal: [0, 0, 1], height: 10)
        let boxLoft = try loft(box, start: end(boxTop, 2), end: nil, sections: [square(12, at: 20)])
        print("LOFTENDS columns: cylinder \(columns(cylinderLoft.report)) box \(columns(boxLoft.report))")
        #expect(columns(boxLoft.report).allSatisfy { $0 <= 17 })
        #expect(columns(cylinderLoft.report).allSatisfy { $0 <= 129 })
    }

    /// A weight that makes a column loop back (or leave through the wall's plane) is refused in words.
    @Test func aWeightThatLoopsAColumnBackIsRefused() throws {
        let part = try box(20, 20, 10)
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        for continuity in [Int32(1), 2] {
            let refused = #expect(throws: OCCTError.self) {
                try loft(part, start: end(top, continuity, weight: 40), end: nil, sections: [square(12, at: 20)])
            }
            #expect(refused?.message == "The tangency weight is too large for this loft.")
        }
        // The weights the gate builds are still fine.
        _ = try loft(part, start: end(top, 2, weight: 2), end: nil, sections: [square(12, at: 20)])
    }

    /// An end face that isn't flat (the cylinder's wall) is refused: the caps and the column directions are built from
    /// the face's flat loop.
    @Test func aCurvedEndFaceIsRefused() throws {
        let (part, _) = try cylinder()
        let wall = try #require(topology(of: part).faces.first { $0.kind != 0 }).index
        for continuity in [Int32(0), 1, 2] {
            let refused = #expect(throws: OCCTError.self) {
                try loft(part, start: end(wall, continuity), end: nil, sections: [square(12, at: 20)])
            }
            #expect(refused?.message == "The loft's end face must be flat.")
        }
    }

    // MARK: Refusals

    @Test func refusals() throws {
        let part = try box(20, 20, 10)
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let triangle = Profile2D(plane: Plane(origin: Vector3(0, 0, 20), normal: .unitZ, xAxis: .unitX), segments: [
            .line(Vector2(0, 0), Vector2(5, 0)), .line(Vector2(5, 0), Vector2(0, 5)), .line(Vector2(0, 5), Vector2(0, 0)),
        ])
        let counts = #expect(throws: OCCTError.self) { try loft(part, start: end(top, 2), end: nil, sections: [triangle]) }
        #expect(counts?.message == "Every loft section needs the same number of segments.")
        let noPart = #expect(throws: OCCTError.self) { try loft(nil, start: end(1, 2), end: nil, sections: [square(12, at: 20)]) }
        #expect(noPart?.message == "Pick a face of the part for the loft's start.")
        let alone = #expect(throws: OCCTError.self) { try loft(part, start: end(top, 2), end: nil, sections: []) }
        #expect(alone?.message == "A loft needs at least two sections.")
    }
}
