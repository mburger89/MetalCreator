import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2 of G-b: corners (MakeFilling, G2 else G1 else fail), tangent chains, the weight refusal.
struct G2FilletTests {
    typealias Built = (shape: OCCTShape, history: [OCCTHistoryRecord], report: occt_g2_report)
    let helper = G2FilletSpikeTests()

    func build(_ shape: OCCTShape, midpoints: [[Double]], radius: Double, weight: Double = 1) throws -> Built {
        let edges = try OCCTKernel.serialized { try helper.topology(of: shape) }
        let ids = try midpoints.map { try helper.edge(edges, near: $0) }
        return try OCCTKernel.serialized { try shape.blendedCurvatureContinuous(edges: ids, size: radius, weight: weight) }
    }

    func cornerGaps(_ report: occt_g2_report) -> [occt_g2_seam] {
        withUnsafeBytes(of: report.corner_seams) { raw in
            Array(raw.bindMemory(to: occt_g2_seam.self).prefix(Int(report.corner_seam_count)))
        }
    }

    func expectSpringsG2(_ built: Built, seams: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let g = helper.gaps(built.report)
        #expect(built.report.seam_count == seams, sourceLocation: sourceLocation)
        #expect(g.position <= 1e-4, sourceLocation: sourceLocation)
        #expect(g.angle <= 0.01, sourceLocation: sourceLocation)
        #expect(g.curvatureRatio <= 1, sourceLocation: sourceLocation)
        #expect(OCCTKernel.serialized { built.shape.validity } == .valid, sourceLocation: sourceLocation)
    }

    func plate() throws -> OCCTShape {
        let segments = ClockwiseArcConformanceTests.notchedPlate()
        return try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
    }

    @Test func aBoxCornerIsCountedOnce() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let built = try build(box, midpoints: [[10, 0, 10], [0, 10, 10], [0, 0, 5]], radius: 2)
        expectSpringsG2(built, seams: 6)
        let corner = cornerGaps(built.report)
        print("G2FILLET box corner: corners \(built.report.corners) g2 \(built.report.g2_corners) g1 \(built.report.g1_corners)"
            + " strips \(helper.sectionCounts(built.report))")
        for seam in corner {
            print("G2FILLET box corner seam: position \(seam.position) angle \(seam.angle_degrees)"
                + " curvature \(seam.curvature) ratio \(seam.curvature_ratio)")
        }
        #expect(built.report.corners == 1)
        #expect(corner.count == 3)
        for seam in corner {
            #expect(seam.position <= 1e-4)
            #expect(seam.angle_degrees <= 0.01)
        }
        // The box's right-angle corner is one G2 patch (G2FilletCornerTests holds the patch to its tolerances).
        #expect(built.report.g2_corners + built.report.g1_corners == 1)
    }

    @Test func anOpenChainEnds() throws {
        let slab = try OCCTKernel.serialized { try OCCTShape.box(40, 20, 3) }
        let built = try build(slab, midpoints: [[20, 0, 3]], radius: 1)
        expectSpringsG2(built, seams: 2)
        #expect(built.report.corners == 0)
        #expect(built.report.corner_seam_count == 0)
    }

    @Test func aTangentChainBuilds() throws {
        let segments: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)),
            .arc(center: Vector2(20, 5), radius: 5, start: .degrees(-90), end: .degrees(90)),
            .line(Vector2(20, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        let shape = try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
        let built = try build(shape, midpoints: [[10, 0, 10], [25, 5, 10], [10, 10, 10]], radius: 1)
        print("G2FILLET chain: strips \(built.report.strips) sections \(helper.sectionCounts(built.report))")
        #expect(built.report.strips == 3)
        #expect(built.report.g1_joins == 0, "a line into a tangent arc has no kink")
        // Strip-to-strip seams are not promised G2 and are not measured: the springs are.
        expectSpringsG2(built, seams: 6)
    }

    @Test func aCylinderNeighbourIsG2() throws {
        let built = try build(try plate(), midpoints: [[14, 10, 5]], radius: 1)
        expectSpringsG2(built, seams: 2)
    }

    @Test func theArcEdgeOfTheNotchIsG2() throws {
        let built = try build(try plate(), midpoints: [[10, 6, 10]], radius: 1)
        print("G2FILLET arc edge: sections \(helper.sectionCounts(built.report))")
        expectSpringsG2(built, seams: 2)
    }

    @Test func extremeWeightsStayValid() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let light = try build(box, midpoints: [[10, 0, 10]], radius: 2, weight: 0.1)
        expectSpringsG2(light, seams: 2)
        // At 2.0 a right angle's sections pass the neighbours' faces: refused with exactly the weight message.
        let error = #expect(throws: OCCTError.self) {
            try build(box, midpoints: [[10, 0, 10]], radius: 2, weight: 2)
        }
        #expect(error?.message == "The tangency weight is too large for this fillet.")
    }
}

extension G2FilletTests {
    /// A 270 degree arc (a pac-man's body) filleted r 0.5: the arc needs many sections (69 with local refinement).
    @Test func aLongArcNeedsManySections() throws {
        let c = 5 * 0.7071067811865476
        let segments: [Segment2D] = [
            .arc(center: Vector2(0, 0), radius: 5, start: .degrees(45), end: .degrees(315)),
            .line(Vector2(c, -c), Vector2(0, 0)), .line(Vector2(0, 0), Vector2(c, c)),
        ]
        let shape = try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
        let started = ContinuousClock.now
        let built = try build(shape, midpoints: [[-5, 0, 10]], radius: 0.5)
        print("G2FILLET 270 degree arc: sections \(helper.sectionCounts(built.report)) in \(ContinuousClock.now - started)")
        #expect(helper.sectionCounts(built.report).allSatisfy { $0 > 9 && $0 <= 129 })
        expectSpringsG2(built, seams: 2)
    }
}

extension G2FilletTests {
    /// A 10 x 10 plate, 3 thick, with a diameter 4 through-hole: one closed circular edge on top.
    func holedPlate() throws -> OCCTShape {
        let profile = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                                holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])
        return try OCCTKernel.serialized { try OCCTShape.extrude(profile, distance: 3).0 }
    }

    @Test func aHoleEdgeHasAClosedG2Strip() throws {
        let plate = try holedPlate()
        let edges = try OCCTKernel.serialized { try helper.topology(of: plate) }
        let candidates = edges.filter { abs($0.mid[2] - 3) < 1e-9 && abs(hypot($0.mid[0] - 1, $0.mid[1] - 1) - 2) < 1e-6 }
        let hole = try #require(candidates.first)
        let built = try build(plate, midpoints: [hole.mid], radius: 0.5)
        print("G2FILLET hole edge: sections \(helper.sectionCounts(built.report))")
        expectSpringsG2(built, seams: 2)
        #expect(built.report.corners == 0)
    }

    /// r 1 beside a notch cylinder of R 5 (it curves away from its tangent plane by about 0.018 mm): not refused at w = 1.
    @Test func aCylinderNeighbourOfR5IsNotRefusedAtWeightOne() throws {
        let segments: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(15, 10)),
            .arc(center: Vector2(10, 10), radius: 5, start: .degrees(0), end: .degrees(-180)),
            .line(Vector2(5, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        let shape = try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
        let built = try build(shape, midpoints: [[15, 10, 5]], radius: 1)
        expectSpringsG2(built, seams: 2)
    }

    /// The same beside the convex cylinder of a half disc.
    @Test func aConvexCylinderNeighbourOfR5IsNotRefusedAtWeightOne() throws {
        let segments: [Segment2D] = [
            .arc(center: Vector2(0, 0), radius: 5, start: .degrees(0), end: .degrees(180)),
            .line(Vector2(-5, 0), Vector2(5, 0)),
        ]
        let shape = try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: 10).0 }
        let built = try build(shape, midpoints: [[5, 0, 5]], radius: 1)
        expectSpringsG2(built, seams: 2)
    }
}
