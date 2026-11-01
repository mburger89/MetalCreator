import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2d-2 of G-b (a gated spike): one three-sided Bezier patch over the box's three-fillet corner hole, with no centre
/// point and no inner seams. The gate: the three strip-to-corner seams inside the tolerances, measured on the final
/// solid; the patch regular (normal defined, principal curvatures bounded); the solid valid.
struct G2CornerTriangleTests {
    let base = G2FilletTests()

    struct Metrics {
        var degree = 0.0, blockMismatch = 0.0, directionCosine = 0.0, maxCurvature = 0.0, minSine = 0.0
        var buildMilliseconds = 0.0, maxNearCorner = 0.0, maxInterior = 0.0, lambda0 = 0.0, lambda1 = 0.0
        var samples = 0.0, rawMismatch = 0.0, iterations = 0.0, largestFreedom = 0.0
    }

    func build(_ shape: OCCTShape, midpoints: [[Double]], radius: Double,
               degree: Int = 17) throws -> (G2FilletTests.Built, Metrics) {
        let edges = try OCCTKernel.serialized { try base.helper.topology(of: shape) }
        let ids = try midpoints.map { try base.helper.edge(edges, near: $0) }
        return try OCCTKernel.serialized {
            occt_test_g2_corner_spike(2)
            occt_test_g2_corner_degree(Int32(degree))
            defer { occt_test_g2_corner_spike(0) }
            let built = try shape.blendedCurvatureContinuous(edges: ids, size: radius, weight: 1)
            var out = [Double](repeating: 0, count: 16)
            occt_test_g2_corner_metrics(&out)
            return (built, Metrics(degree: out[0], blockMismatch: out[1], directionCosine: out[2], maxCurvature: out[3],
                                   minSine: out[4], buildMilliseconds: out[5], maxNearCorner: out[6], maxInterior: out[7],
                                   lambda0: out[8], lambda1: out[9], samples: out[10], rawMismatch: out[11], iterations: out[12],
                                   largestFreedom: out[13]))
        }
    }

    /// Degree 17 is the least that holds every layer exactly (the second layer is of degree 15); 21 and up lose the corner
    /// blocks to the conditioning of the Bernstein collocation (mismatch above 1e-6) and fall back to the G1 refill.
    @Test(arguments: [17, 19]) func aBoxCornerIsOneThreeSidedPatch(degree: Int) throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let (built, metrics) = try build(box, midpoints: [[10, 0, 10], [0, 10, 10], [0, 0, 5]], radius: 2, degree: degree)
        let seams = base.cornerGaps(built.report)
        print("G2TRI degree \(degree) corners \(built.report.corners) g2 \(built.report.g2_corners)"
            + " g1 \(built.report.g1_corners) seams \(seams.count)")
        print("G2TRI metrics \(metrics)")
        for seam in seams {
            print("G2TRI seam: position \(seam.position) angle \(seam.angle_degrees)"
                + " curvature \(seam.curvature) ratio \(seam.curvature_ratio)")
        }
        let validity = OCCTKernel.serialized { built.shape.validity }
        print("G2TRI validity \(validity)")
        #expect(validity == .valid)
        #expect(built.report.g2_corners == 1)
        #expect(built.report.g1_corners == 0)
        #expect(seams.count == 3)
        for seam in seams {
            #expect(seam.position <= 1e-4)
            #expect(seam.angle_degrees <= 0.01)
            #expect(seam.curvature_ratio <= 1)
        }
        #expect(metrics.minSine > 0.05)
        #expect(metrics.maxCurvature < 2 / 2.0) // below twice the strips' 1 / r = 0.5 /mm
        base.expectSpringsG2(built, seams: 6)
    }
}
