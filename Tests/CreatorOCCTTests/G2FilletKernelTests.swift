import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 3 of G-b: `FilletProfile` through the `Kernel`.
struct G2FilletKernelTests {
    /// Edges of a 20 x 20 x 10 box picked by what they are: the top front edge and the three at the (0, 0) corner.
    func cornerEdges(of solid: Solid) throws -> [EdgeID] {
        let (low, high) = (solid.bounds.min, solid.bounds.max)
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        let found = solid.topology.edges.filter { edge in
            let m = edge.midpoint
            return (near(m.y, low.y) && near(m.z, high.z)) || (near(m.x, low.x) && near(m.z, high.z))
                || (near(m.x, low.x) && near(m.y, low.y))
        }
        #expect(found.count == 3)
        return found.map(\.id)
    }

    func shape(of solid: Solid) throws -> OCCTShape {
        try #require((solid.storage as? OCCTSolidStorage)?.shape)
    }

    @Test func g2FacesAndTagsEqualG1s() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let edges = try cornerEdges(of: solid)
        let circular = try await kernel.fillet(solid, edges: edges, radius: 2, profile: .circular, tag: newTag())
        let g2 = try await kernel.fillet(solid, edges: edges, radius: 2, profile: .curvatureContinuous(weight: 1), tag: newTag())
        #expect(g2.solid.topology.faces.count == circular.solid.topology.faces.count)
        func roles(_ solid: Solid) -> Set<TopoRole> { Set(solid.topology.faces.flatMap(\.tags).map(\.role)) }
        #expect(roles(g2.solid) == roles(circular.solid))
        #expect(circular.tangentOnlyCorners == 0 && circular.tangentOnlyJoins == 0)
        // The three-edge corner is the G1 refill, counted.
        #expect(g2.tangentOnlyCorners == 1)
    }

    @Test func g2IsValidAndSeamsPass() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let edges = try cornerEdges(of: solid)
        let made = try await kernel.blendReporting(solid, edges: edges, size: 2, chamfer: false,
                                                   profile: .curvatureContinuous(weight: 1), tag: newTag())
        let report = try #require(made.report)
        #expect(report.seam_count == 6)
        #expect(G2SeamCheck.promised.passes(report, 2))
        #expect(OCCTKernel.serialized { (try? shape(of: made.solid))?.isValid } == true)
    }

    /// A strip that misses the promise fails with the strip sentence and names the largest radius whose G2 build passes.
    /// A check that rejects every radius above 2.5 mm stands in for the strip that misses it.
    @Test func aMissedStripNamesTheLargestRadius() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let edge = try #require(solid.topology.edges.first {
            isClose($0.midpoint.y, solid.bounds.min.y) && isClose($0.midpoint.z, solid.bounds.max.z)
        })
        let error = await #expect(throws: KernelError.self) {
            try await kernel.filletReporting(solid, edges: [edge.id], radius: 4, profile: .curvatureContinuous(weight: 1),
                                             tag: newTag(), seamCheck: G2SeamCheck { _, radius in radius <= 2.5 })
        }
        #expect(error == .notCurvatureContinuous(radius: 4, largest: 2.5))
        #expect(error?.userMessage == "The fillet can't be made curvature continuous at this radius. "
            + "Radius 4 mm is too large for the selected edges (max ≈ 2.5 mm).")
    }

    @Test func aWeightThatIsNotPositiveIsRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let edges = try cornerEdges(of: solid)
        for weight in [0.0, -1, .nan] {
            let error = await #expect(throws: KernelError.self) {
                try await kernel.fillet(solid, edges: edges, radius: 2, profile: .curvatureContinuous(weight: weight), tag: newTag())
            }
            #expect(error == .weightNotPositive)
        }
    }

    @Test func theOldRequirementIsACircularFillet() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let edges = try cornerEdges(of: solid)
        let old = try await kernel.fillet(solid, edges: edges, radius: 2, tag: newTag())
        let circular = try await kernel.fillet(solid, edges: edges, radius: 2, profile: .circular, tag: newTag())
        #expect(old.topology.faces.count == circular.solid.topology.faces.count)
        let volumes = try OCCTKernel.serialized { (try shape(of: old).volume, try shape(of: circular.solid).volume) }
        #expect(volumes.0 == volumes.1)
    }
}
