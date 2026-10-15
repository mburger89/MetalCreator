import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// A faceted solid from a mesh (implicit spec §3.6, §4.7): the kernel builds a planar face per triangle, sews them, merges the faces
/// that lie in one plane and checks the result. The solid goes to Output and exports as STEP like any other. Refused above 100,000
/// triangles, which a boundary representation cannot take in reasonable time. While an export streams, the stream is meshed into
/// memory first, with its Decimate stages applied (so decimating is how a big part gets under the limit).
public enum MeshToSolidNode: NodeDefinition {
    public static let typeID = "creator.meshToSolid"
    public static let displayName = "Mesh to Solid"
    public static let category = NodeCategory.mesh
    public static let readsMeshQuality = true
    public static let triangleLimit = 100_000
    public static let inputs = [SocketSpec("mesh", .mesh)]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Mesh to Solid", controls: [
            .note("Makes a faceted solid, up to 100,000 triangles. Decimate the mesh first if it has more."),
        ]),
    ]

    /// The refusal above the limit, in the spec's words.
    static func requireWithinLimit(_ triangles: Int) throws {
        guard triangles > triangleLimit else { return }
        let count = triangles.formatted(.number.locale(.messages)), limit = triangleLimit.formatted(.number.locale(.messages))
        throw NodeError.invalidValue("Mesh has \(count) triangles; Mesh to Solid takes at most \(limit). "
            + "Decimate it first or coarsen the resolution.")
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (mesh, warnings) = try await MeshInput.collected(try inputs.scalar("mesh"), socket: "mesh", limit: triangleLimit,
                                                              context: context)
        try requireWithinLimit(mesh.triangleCount)
        let welded = MeshWelder.weld(positions: mesh.positions, triangles: mesh.triangles)
        let solid = try await kernel.meshToSolid(positions: welded.positions, triangles: welded.triangles, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)], warnings: warnings)
    }
}
