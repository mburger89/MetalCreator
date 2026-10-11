import CreatorGraph
import CreatorKernel

/// Describes a tree (7a spec §4): its depth, how many branches hold items, how many items in all, and the items in
/// each branch, in path order. The paths themselves are shown by the inspector's tree list, not here, because no
/// socket carries text.
public enum TreeStatisticsNode: NodeDefinition {
    public static let typeID = "creator.treeStatistics"
    public static let displayName = "Tree Statistics"
    public static let category = NodeCategory.lists
    public static let inputs = [SocketSpec("tree", .any, access: .tree)]
    public static let outputs = [
        SocketSpec("depth", .integer, unit: .count),
        SocketSpec("branches", .integer, unit: .count),
        SocketSpec("items", .integer, unit: .count),
        SocketSpec("counts", .integer, unit: .count),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        let leaves = tree.leaves
        var outputs = NodeOutputs([
            "depth": .integer(tree.depth), "branches": .integer(leaves.count), "items": .integer(tree.itemCount),
        ])
        outputs.lists["counts"] = leaves.map { .integer($0.items.count) }
        return outputs
    }
}
