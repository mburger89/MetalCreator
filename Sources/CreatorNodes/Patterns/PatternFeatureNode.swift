import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The general pattern shortcut (patterns spec §5): any tool solid, built at the origin facing +Z, unioned onto or
/// subtracted from the part at every placement. It is Place + Boolean underneath: the same as wiring Place's copies
/// into a Boolean's `tools`, in one node, with one kernel call to place the copies and one to combine them.
///
/// Tools and placements are matched as Place's are (`InstanceGrid`), so a list or tree of tools gives each instance its own size. An instance
/// whose tool misses the part doesn't fail the node: it warns with the count ("3 of 24 features miss the part.").
public enum PatternFeatureNode: NodeDefinition {
    public static let typeID = "creator.patternFeature"
    public static let displayName = "Pattern Feature"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let operations = ["Union", "Subtract"]
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("tool", .solid, access: .tree),
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("operation", .integer, defaultValue: .integer(1)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Pattern Feature", controls: [.segmented("operation", options: operations)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try PlacementMoves.requireSingleValues(context)
        let op: BooleanOp = [.union, .subtract][try inputs.choice("operation", options: operations)]
        let part = try inputs.solid("part")
        let grid = try InstanceGrid(inputs, ["placements", "tool"])
        guard grid.count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let request = PatternApply.Request(operation: op, part: part, tools: try grid.solids("tool"), planes: try grid.planes("placements"),
                                           grid: grid, nouns: PatternApply.Nouns(singular: "feature", plural: "features"))
        return try await PatternApply.run(request, kernel: kernel, context: context)
    }
}
