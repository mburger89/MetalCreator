import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Turns a B-rep solid into its signed distance (implicit spec §3.1, §4.4): the kernel tessellates it at `tolerance`, a BVH measures the
/// distance to the triangles and the sign comes from the triangles' pseudonormals, and the result is baked on a grid of blocks. The
/// bake is cached (`ImplicitBakeCache`), so an edit downstream of this node does not bake again. After this node everything is implicit
/// until Mesh makes triangles.
public enum ToImplicitNode: NodeDefinition {
    public static let typeID = "creator.toImplicit"
    public static let displayName = "To Implicit"
    public static let category = NodeCategory.implicit
    public static let minimumTolerance = 0.001
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("tolerance", .number, defaultValue: .number(0.01), unit: .millimetres, range: minimumTolerance...1),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "To Implicit", controls: [.slider("tolerance")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let tolerance = try inputs.number("tolerance")
        guard tolerance.isFinite, tolerance >= minimumTolerance else {
            let smallest = minimumTolerance.formatted(.number.precision(.fractionLength(0...3)).locale(.messages))
            throw NodeError.invalidValue("“tolerance” must be at least \(smallest) mm.")
        }
        let baked: ImplicitBakeCache.Baked
        do {
            baked = try await ImplicitBakeCache.shared.baked(for: solid, tolerance: tolerance, kernel: kernel)
        } catch let error as MeshDistanceError {
            throw NodeError.invalidValue(error.userMessage)
        }
        // A solid named for what it is: the node's own name when the person gave it one.
        let label = context.node.name == displayName ? "solid" : context.node.name
        var warnings: [String] = []
        let wanted = DistanceBaker.spacing(forTolerance: tolerance)
        if baked.spacing > wanted * 1.001 {
            let (used, asked) = (baked.spacing.millimetreText(locale: .messages), wanted.millimetreText(locale: .messages))
            warnings.append("The part is big for this tolerance, so it was measured every \(used) mm instead of every \(asked) mm; "
                + "thin features may be lost.")
        }
        return NodeOutputs(["implicit": .implicit(ImplicitSolid.baked(baked.blocks, label: label).reference)], warnings: warnings)
    }
}
