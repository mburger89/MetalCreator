import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import Testing
@testable import CreatorNodes

/// Decimate promises a closed manifold, so Check Trapped Volumes must be able to ask what is inside its output. The mesher leaves
/// vertices within a micron of one another joined by slivers; decimating those apart left two vertices at one place, and the check's
/// weld (1e-6) then found an edge with four faces: "This mesh isn't closed".
struct DecimateThenCheckTests {
    @Test(arguments: [0.0001, 0.001, 0.01, 0.05], [1.0, 2.0])
    func aDecimatedShellIsCheckedLikeTheMeshItCameFrom(tolerance: Double, thickness: Double) async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(thickness)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.5), "preview resolution": .number(0.5)])
        let decimate = h.add(DecimateNode.self, ["tolerance": .number(tolerance)])
        let direct = h.add(CheckTrappedVolumesNode.self)
        let after = h.add(CheckTrappedVolumesNode.self)
        h.wire(sphere, "implicit", to: shell, "implicit")
        h.wire(shell, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: decimate, "mesh")
        h.wire(mesh, "mesh", to: direct, "mesh")
        h.wire(decimate, "mesh", to: after, "mesh")
        let report = try await h.run([direct, after])
        #expect(report.error(direct) == nil)
        #expect(report.error(after) == nil, "tolerance \(tolerance): \(String(describing: report.error(after)))")
        let voids = { (node: Node) in report.triangleMesh(node)?.inspectorFacts.first { $0.label == "Enclosed voids" }?.value }
        #expect(voids(direct) == "1", "\(String(describing: voids(direct)))")
        #expect(voids(after) == voids(direct), "\(String(describing: voids(direct))) before, \(String(describing: voids(after))) after")
    }
}
