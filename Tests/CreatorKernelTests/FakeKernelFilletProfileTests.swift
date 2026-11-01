import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelFilletProfileTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func bothProfilesGiveTheSameTopology() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let edges = solid.topology.edges.prefix(2).map(\.id)
        let circular = try await kernel.fillet(solid, edges: edges, radius: 1, profile: .circular, tag: tag)
        let smooth = try await kernel.fillet(solid, edges: edges, radius: 1, profile: .curvatureContinuous(weight: 1), tag: tag)
        #expect(smooth.solid.topology.faces.count == circular.solid.topology.faces.count)
        #expect(Set(smooth.solid.topology.faces.flatMap(\.tags)) == Set(circular.solid.topology.faces.flatMap(\.tags)))
        #expect(smooth.tangentOnlyCorners == 0 && smooth.tangentOnlyJoins == 0)
        let old = try await kernel.fillet(solid, edges: edges, radius: 1, tag: tag)
        #expect(old.topology.faces.count == circular.solid.topology.faces.count)
    }

    @Test func aWeightThatIsNotPositiveIsRefused() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: [solid.topology.edges[0].id], radius: 1,
                                    profile: .curvatureContinuous(weight: 0), tag: tag)
        }
    }
}
