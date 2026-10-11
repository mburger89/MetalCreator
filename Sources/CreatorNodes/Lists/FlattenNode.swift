import CreatorGraph
import CreatorKernel

/// Removes nesting from a tree (7a spec §4): all of it, or down to a given level. `level` is how many levels of
/// branches to keep from the outside; left empty, none are kept and the result is one flat list. Items keep their
/// order, so flattening a 3 × 8 tree gives the 24 items row by row.
public enum FlattenNode: NodeDefinition {
    public static let typeID = "creator.flatten"
    public static let displayName = "Flatten"
    public static let category = NodeCategory.lists
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("level", .integer, unit: .count, optional: true),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let inspector = [InspectorSection(title: "Flatten", controls: [.integer("level")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let keep = inputs.has("level") ? try inputs.integer("level") : 0
        guard keep >= 0 else { throw NodeError.invalidValue("“level” can't be negative. Leave it empty to flatten everything.") }
        return NodeOutputs(trees: ["tree": try inputs.tree("tree").flattened(keeping: keep)])
    }
}
