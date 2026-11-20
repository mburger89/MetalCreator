import CreatorGraph
import CreatorKernel

/// A closed solid divided by sheets or solids into its pieces (NS-5, R13).
public enum SplitSolidNode: NodeDefinition {
    public static let typeID = "creator.splitSolid"
    public static let displayName = "Split Solid"
    public static let category = NodeCategory.solid
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("tools", .solid, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("solids", .solid, access: .list)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        try ClosedSolidCheck.requireForSplitSolid(solid)
        let tools = inputs.has("tools") ? try inputs.solids("tools") : []
        guard !tools.isEmpty else { return NodeOutputs(lists: ["solids": [.solid(solid)]]) }
        let split = try await kernel.splitSolid(solid, by: tools, tag: context.tag)
        return NodeOutputs(lists: ["solids": split.pieces.map { .solid($0) }], warnings: split.warnings)
    }
}
