import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The final review's finding: a fillet with more strips than the report's array holds is judged whole.
struct G2FilletManyStripTests {
    /// A disc of radius 20 made of 40 arcs (a tangent chain all the way round), 10 mm tall.
    func arcDisc(_ kernel: OCCTKernel) async throws -> Solid {
        let count = 40
        let segments: [Segment2D] = (0..<count).map { i in
            .arc(center: Vector2(0, 0), radius: 20, start: .degrees(360.0 * Double(i) / Double(count)),
                 end: .degrees(360.0 * Double(i + 1) / Double(count)))
        }
        return try await kernel.extrude(Profile2D(plane: .xy, segments: segments), distance: 10, mode: .oneSided, tag: newTag())
    }

    @Test func aManyStripFilletIsJudgedWhole() async throws {
        let kernel = OCCTKernel()
        let solid = try await arcDisc(kernel)
        let top = solid.topology.edges.filter { isClose($0.midpoint.z, solid.bounds.max.z) }.map(\.id)
        #expect(top.count == 40)
        let made = try await kernel.blendReporting(solid, edges: top, size: 0.5, chamfer: false,
                                                   profile: .curvatureContinuous(weight: 1), tag: newTag())
        let report = try #require(made.report)
        #expect(report.seams_total > 64)
        #expect(report.seam_count == 64)
        #expect(report.seams_judged == 1)
        #expect(G2SeamCheck.promised.passes(report, 0.5))
        #expect(OCCTKernel.serialized { (made.solid.storage as? OCCTSolidStorage)?.shape.isValid } == true)
    }

    /// A report whose sample is shorter than the seams it counts passes only when the shim says it judged them all.
    @Test func theSeamCheckRefusesAnUnjudgedOverflow() {
        var report = occt_g2_report()
        report.seams_total = 80
        report.seam_count = 64
        #expect(!G2SeamCheck.promised.passes(report, 1))
        report.seams_judged = 1
        #expect(G2SeamCheck.promised.passes(report, 1))
    }
}
