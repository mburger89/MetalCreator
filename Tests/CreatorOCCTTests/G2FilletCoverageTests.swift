import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2b of G-b: strips that end slantwise on a face and chains that run into a wall are built past their end and
/// trimmed by the end face. The run-out edge is a crease and is not measured.
struct G2FilletCoverageTests {
    let base = G2FilletTests()

    /// The bracket's plate (Width 60 x 40, R4, 6 thick) with its flange (60 wide, 8 thick, 30 high) on the back edge.
    func bracketPlate() throws -> OCCTShape {
        let profile = Profile2D.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy)
        return try OCCTKernel.serialized {
            let plate = try OCCTShape.extrude(profile, distance: 6).0
            let flange = try OCCTShape.box(60, 8, 30)
                .transformed(by: Transform(translation: Vector3(-30, 12, 0))).0
            return try OCCTShape.boolean(.union, plate, [flange]).0
        }
    }

    /// One edge of the plate's tangent outline chain, which runs into the flange wall: OCCT propagates the fillet
    /// along the whole chain (front line, two R4 corners, two sides), so five strips are built.
    @Test func aChainIntoAWallBuilds() throws {
        let plate = try bracketPlate()
        let built = try base.build(plate, midpoints: [[30, -2, 6]], radius: 1)
        print("G2COVER chain into wall: strips \(built.report.strips) sections \(base.helper.sectionCounts(built.report))")
        #expect(built.report.strips == 5)
        base.expectSpringsG2(built, seams: 10)
        try expectVolumeNearCircular(plate, midpoints: [[30, -2, 6]], radius: 1, length: 125, built: built)
    }

    /// The G2 blend removes a little more or less material than the circular one (within a tenth of r squared per mm).
    func expectVolumeNearCircular(_ shape: OCCTShape, midpoints: [[Double]], radius: Double, length: Double, built: G2FilletTests.Built,
                                  sourceLocation: SourceLocation = #_sourceLocation) throws {
        let circular = try base.build(shape, midpoints: midpoints, radius: radius, weight: 0)
        let (g2Volume, g1Volume) = OCCTKernel.serialized { (built.shape.volume, circular.shape.volume) }
        print("G2COVER volumes: G2 \(g2Volume) circular \(g1Volume)")
        #expect(abs(g2Volume - g1Volume) < 0.1 * radius * radius * length, sourceLocation: sourceLocation)
    }

    /// A drafted prism: a 20 square at the bottom, a 16 square at the top, ruled.
    func draftedPrism() throws -> OCCTShape {
        let bottom = Profile2D.rectangle(width: 20, height: 20, plane: .xy)
        let top = Profile2D.rectangle(width: 16, height: 16,
                                      plane: Plane(origin: Vector3(0, 0, 10), normal: .unitZ, xAxis: .unitX))
        return try OCCTKernel.serialized { try OCCTShape.loft([bottom, top], ruled: true).0 }
    }

    @Test func aDraftedRunOutBuilds() throws {
        let built = try base.build(try draftedPrism(), midpoints: [[0, -8, 10]], radius: 1)
        print("G2COVER drafted: sections \(base.helper.sectionCounts(built.report))")
        base.expectSpringsG2(built, seams: 2)
        try expectVolumeNearCircular(try draftedPrism(), midpoints: [[0, -8, 10]], radius: 1, length: 16, built: built)
    }

    @Test func aSlantedArcRunOutBuilds() throws {
        let c = 5 * 0.8660254037844386
        let segments: [Segment2D] = [
            .arc(center: Vector2(0, 0), radius: 5, start: .degrees(30), end: .degrees(330)),
            .line(Vector2(c, -2.5), Vector2(c, 2.5)),
        ]
        let shape = try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
        let built = try base.build(shape, midpoints: [[-5, 0, 10]], radius: 0.5)
        print("G2COVER slanted arc: sections \(base.helper.sectionCounts(built.report))")
        base.expectSpringsG2(built, seams: 2)
        try expectVolumeNearCircular(shape, midpoints: [[-5, 0, 10]], radius: 0.5, length: 26, built: built)
    }
}
