import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Marks solids, meshes and curves for preview and export (spec §7.1, Output; implicit spec §2.3). The node's name is the export name.
/// It passes every wired solid through as one list, and every wired mesh as another: an implicit solid wired into `mesh` is meshed
/// here, at the Mesh node's default settings (at export resolution when the run is an export). Its `.output` category makes
/// `NodeRegistry.makeNode` flag new Output nodes with `isOutput`, so they join the evaluation
/// demand (spec §4.4) however they are created.
public enum OutputNode: NodeDefinition {
    public static let typeID = "creator.output"
    public static let displayName = "Output"
    public static let category = NodeCategory.output
    public static let readsMeshQuality = true
    public static let inputs = [
        SocketSpec("solid", .solid, access: .list, optional: true),
        SocketSpec("mesh", .mesh, access: .list, optional: true),
        SocketSpec("curve", .curve, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("solid", .solid), SocketSpec("mesh", .mesh), SocketSpec("curve", .curve)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solids = inputs.has("solid") ? try inputs.solids("solid") : []
        let made = inputs.has("mesh")
            ? try await MeshInput.payloads(try inputs.list("mesh"), socket: "mesh", context: context) : (payloads: [], warnings: [])
        let curves = inputs.has("curve")
            ? try await CurveInput.loops(try inputs.curves("curve"), holes: .all, kernel: kernel, tag: context.tag) : []
        var warnings = made.warnings
        if solids.isEmpty, made.payloads.isEmpty, curves.isEmpty { warnings.append("There is nothing to preview or export.") }
        var output = NodeOutputs(lists: ["solid": solids.map(Scalar.solid), "mesh": made.payloads.map(Scalar.mesh),
                                           "curve": curves.map(Scalar.curve),
        ])
        output.warnings = warnings
        return output
    }
}
