import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2d of G-b (a gated spike): a G2 corner patch for the box's three-fillet corner, built as three quadrilateral
/// Bezier patches. The gate: every strip-to-corner seam and every inner seam inside the tolerances, measured on the
/// final solid, and the solid valid.
struct G2CornerSpikeTests {
    let base = G2FilletTests()

    func build(_ shape: OCCTShape, midpoints: [[Double]], radius: Double) throws -> G2FilletTests.Built {
        let edges = try OCCTKernel.serialized { try base.helper.topology(of: shape) }
        let ids = try midpoints.map { try base.helper.edge(edges, near: $0) }
        return try OCCTKernel.serialized {
            occt_test_g2_corner_spike(1)
            defer { occt_test_g2_corner_spike(0) }
            return try shape.blendedCurvatureContinuous(edges: ids, size: radius, weight: 1)
        }
    }

    /// Result of the spike: the six strip-to-corner seams are G2 to rounding and the solid is valid, but the patch's
    /// parametrization is singular at the centre (mirror C1 across seams at 60 degrees forces the 2 x 2 control block there
    /// onto the centre), so the three inner seams miss the angle tolerance where it is read at the centre (and the
    /// curvature there is unbounded). BLOCKED, see task-2d-report.md.
    @Test func aBoxCornerPatchIsG2AwayFromTheCentre() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let built = try build(box, midpoints: [[10, 0, 10], [0, 10, 10], [0, 0, 5]], radius: 2)
        let seams = base.cornerGaps(built.report)
        print("G2CORNER corners \(built.report.corners) g2 \(built.report.g2_corners) g1 \(built.report.g1_corners) seams \(seams.count)")
        for seam in seams {
            print("G2CORNER seam: position \(seam.position) angle \(seam.angle_degrees) curvature \(seam.curvature)"
                + " ratio \(seam.curvature_ratio)")
        }
        let validity = OCCTKernel.serialized { built.shape.validity }
        #expect(validity == .valid)
        #expect(built.report.g2_corners == 1)
        #expect(built.report.g1_corners == 0)
        #expect(seams.count == 9)
        // The order is: for each of the three end curves, its two halves (strip to corner) then the seam (corner to corner).
        for (index, seam) in seams.enumerated() {
            #expect(seam.position <= 1e-4)
            if index % 3 != 2 {
                #expect(seam.angle_degrees <= 0.01)
                #expect(seam.curvature_ratio <= 1)
            } else {
                withKnownIssue("the quadrilaterals' parametrization is singular at the centre") {
                    #expect(seam.angle_degrees <= 0.01)
                }
            }
        }
        base.expectSpringsG2(built, seams: 6)
    }
}

extension G2CornerSpikeTests {
    /// Not part of the gate: a top edge and its vertical edge, the third edge at their vertex left sharp.
    @Test func aTopEdgeAndAVerticalEdgeProbe() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        do {
            let built = try build(box, midpoints: [[10, 0, 10], [0, 0, 5]], radius: 2)
            print("G2CORNER probe two of three: built, strips \(built.report.strips) mitres \(built.report.mitres)")
        } catch {
            print("G2CORNER probe two of three: refused: \(error)")
        }
    }
}
