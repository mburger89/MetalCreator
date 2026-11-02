import COCCT
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// G-b Task 2c: on the acceptance bracket's real pre-fillet solid (plate with holes, unioned with the flange) every
/// edge the circular fillet builds at r 1 also builds as a G2 fillet: valid, with the circular path's history.
@MainActor
struct G2FilletBracketSweepTests {
    @Test func everyBracketEdgeBuilds() async throws {
        let kernel = OCCTKernel()
        let bracket = BracketAcceptanceTests.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let shape = try #require((union.storage as? OCCTSolidStorage)?.shape)
        var circularBuilt = 0, g2Built = 0
        var refused: [String] = []
        for edge in union.topology.edges where !edge.isSeam {
            let id = edge.id
            let circular = try? OCCTKernel.serialized { try shape.blended(edges: [id], size: 1, chamfer: false) }
            guard let circular else { continue }
            circularBuilt += 1
            do {
                let g2 = try OCCTKernel.serialized { try shape.blendedCurvatureContinuous(edges: [id], size: 1, weight: 1) }
                g2Built += 1
                #expect(OCCTKernel.serialized { g2.shape.validity } == .valid, "edge \(id.rawValue)")
                #expect(g2.history == circular.1, "edge \(id.rawValue): the history is the circular path's")
                let report = g2.report
                withUnsafeBytes(of: report.seams) { raw in
                    for seam in raw.bindMemory(to: occt_g2_seam.self).prefix(Int(report.seam_count)) {
                        #expect(seam.position <= 1e-4 && seam.angle_degrees <= 0.01 && seam.curvature_ratio <= 1,
                                "edge \(id.rawValue): spring seam \(seam)")
                    }
                }
            } catch {
                refused.append("edge \(id.rawValue): \(error)")
            }
        }
        print("G2SWEEP circular \(circularBuilt) g2 \(g2Built) refused \(refused)")
        #expect(circularBuilt == 28 && g2Built == 28)
        #expect(refused.isEmpty, "\(refused)")
    }
}
#endif
