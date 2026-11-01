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

extension G2FilletCoverageTests {
    /// A smooth three-section loft (20 square, 24 square, 20 square): its four sides are B-spline faces.
    func smoothLoft() throws -> OCCTShape {
        func square(_ side: Double, _ z: Double) -> Profile2D {
            Profile2D.rectangle(width: side, height: side, plane: Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX))
        }
        return try OCCTKernel.serialized { try OCCTShape.loft([square(20, 0), square(24, 5), square(20, 10)], ruled: false).0 }
    }

    /// A top edge of a smooth loft: its B spring is a B-spline curve on a B-spline face.
    @Test func aLoftNeighbourIsG2() throws {
        let built = try base.build(try smoothLoft(), midpoints: [[0, -10, 10]], radius: 1)
        print("G2COVER loft: sections \(base.helper.sectionCounts(built.report)) gaps \(base.helper.gaps(built.report))")
        base.expectSpringsG2(built, seams: 2)
    }
}

extension G2FilletCoverageTests {
    /// A shape that carries a location (a STEP import can): the weight check and the slanted trim read the faces in
    /// their own frames.
    @Test func aLocatedShapeBuilds() throws {
        let (offset, angle) = (Vector3(5, 3, 2), 0.7)
        let plain = try draftedPrism()
        let prism = try OCCTKernel.serialized { try plain.locatedCopy(translation: offset, rotationAboutZ: angle) }
        let mid = [0 * cos(angle) + 8 * sin(angle) + offset.x, 0 * sin(angle) - 8 * cos(angle) + offset.y, 10 + offset.z]
        let built = try base.build(prism, midpoints: [mid], radius: 1)
        base.expectSpringsG2(built, seams: 2)
    }
}

extension G2FilletCoverageTests {
    /// The four top edges of a box meet at its vertical edges: strips meet in mitres, with no corner patch.
    @Test func aBoxTopOutlineBuilds() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let mids: [[Double]] = [[10, 0, 10], [20, 10, 10], [10, 20, 10], [0, 10, 10]]
        let built = try base.build(box, midpoints: mids, radius: 2)
        print("G2COVER box outline: strips \(built.report.strips) sections \(base.helper.sectionCounts(built.report))")
        #expect(built.report.strips == 4)
        base.expectSpringsG2(built, seams: 8)
        expectMitres(built, count: 4)
        try expectVolumeNearCircular(box, midpoints: mids, radius: 2, length: 80, built: built)
    }

    /// A mitre is a crease between the two strips, as the circular fillet's is (two cylinders meeting at a right
    /// angle are tangent only where they leave the top face): only its position is promised, and it is recorded.
    func expectMitres(_ built: G2FilletTests.Built, count: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(built.report.mitres == Int32(count), sourceLocation: sourceLocation)
        let seams = withUnsafeBytes(of: built.report.mitre_seams) { raw in
            Array(raw.bindMemory(to: occt_g2_seam.self).prefix(Int(built.report.mitre_seam_count)))
        }
        #expect(seams.count == count, sourceLocation: sourceLocation)
        for seam in seams {
            print("G2COVER mitre seam: position \(seam.position) angle \(seam.angle_degrees)")
            #expect(seam.position <= 1e-4, sourceLocation: sourceLocation)
        }
    }

    /// Two top edges that meet at a vertex.
    @Test func twoMeetingEdgesBuild() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let built = try base.build(box, midpoints: [[10, 0, 10], [20, 10, 10]], radius: 2)
        #expect(built.report.strips == 2)
        base.expectSpringsG2(built, seams: 4)
        expectMitres(built, count: 1)
    }
}
