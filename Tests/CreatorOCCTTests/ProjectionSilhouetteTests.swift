#if canImport(CreatorOCCT)
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

extension ProjectionTests {
    /// The bracket's wall seen face-on: a round's tangent edge on the side face has the view direction in its tangent plane, so
    /// it is the silhouette and must draw as an outline (a thick line that "Tangent edges" off keeps), while the round's other
    /// tangent edge, on the face the viewer looks at, stays smooth.
    @Test func aTangentEdgeOnTheSilhouetteIsAnOutline() async throws {
        let solid = try await cornerBox()
        let corner = try #require(solid.topology.edges.first {
            $0.kind == .line && abs(($0.direction ?? .zero).dot(.unitZ)) > 0.999
                && abs($0.midpoint.x - 10) < 1e-6 && abs($0.midpoint.y) < 1e-6
        })
        let filleted = try await kernel.fillet(solid, edges: [corner.id], radius: 2, profile: .circular, tag: tag).solid
        let projection = try await kernel.projection(of: filleted, curves: [], frame: Self.front, options: ProjectionOptions())
        let blend = try #require(filleted.topology.faces.first { $0.kind == .cylinder }).id
        let tangentEdges = filleted.topology.edges.filter { $0.faces.contains(blend) && !$0.isSeam && $0.kind == .line }
        #expect(tangentEdges.count == 2)
        // The edge at x = 10 is the one on the right-hand face (normal +X, square to the view direction).
        let onSilhouette = try #require(tangentEdges.first { abs($0.midpoint.x - 10) < 1e-6 })
        let onFront = try #require(tangentEdges.first { $0.id != onSilhouette.id })
        #expect(edgeIDs(lines(projection, .visible, .outline)).contains(onSilhouette.id))
        #expect(!edgeIDs(lines(projection, .visible, .smooth)).contains(onSilhouette.id))
        #expect(edgeIDs(lines(projection, .visible, .smooth)) == [onFront.id])
    }
}
#endif
