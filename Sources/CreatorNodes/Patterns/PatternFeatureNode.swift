import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The general pattern shortcut (patterns spec §5): any tool solid, built at the origin facing +Z, unioned onto or
/// subtracted from the part at every placement. It is Place + Boolean underneath: the same as wiring Place's copies
/// into a Boolean's `tools`, in one node, with one kernel call to place the copies and one to combine them.
///
/// Tools and placements broadcast as Place's do, so a list of tools gives each instance its own size. An instance
/// whose tool misses the part doesn't fail the node: it warns with the count ("3 of 24 features miss the part.").
public enum PatternFeatureNode: NodeDefinition {
    public static let typeID = "creator.patternFeature"
    public static let displayName = "Pattern Feature"
    public static let category = NodeCategory.patterns
    public static let operations = ["Union", "Subtract"]
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("tool", .solid, access: .list),
        SocketSpec("placements", .plane, access: .list),
        SocketSpec("operation", .integer, defaultValue: .integer(1)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Pattern Feature", controls: [.segmented("operation", options: operations)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let op: BooleanOp = [.union, .subtract][try inputs.choice("operation", options: operations)]
        let planes = try inputs.planes("placements")
        let tools = PatternApply.tools(try inputs.solids("tool"), planes: planes)
        let request = PatternApply.Request(operation: op, part: try inputs.solid("part"), tools: tools, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "feature", plural: "features"))
        return try await PatternApply.run(request, kernel: kernel, context: context)
    }
}
