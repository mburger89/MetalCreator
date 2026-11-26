import CreatorGraph
import CreatorKernel

/// A value taken apart into its closed solids and its open surfaces (NURBS gaps, R3), each keeping its face and edge tags.
public enum SeparateSolidsNode: NodeDefinition {
    public static let typeID = "creator.separateSolids"
    public static let displayName = "Separate Solids"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Solids"
    public static let inputs = [SocketSpec("value", .solid)]
    public static let outputs = [
        SocketSpec("solids", .solid, access: .list),
        SocketSpec("surfaces", .solid, access: .list),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let separated = try await kernel.separated(try inputs.solid("value"), tag: context.tag)
        return NodeOutputs(lists: [
            "solids": separated.solids.map { .solid($0) },
            "surfaces": separated.sheets.map { .solid($0) },
        ])
    }
}
