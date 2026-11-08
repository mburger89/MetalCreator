import CreatorGraph
import CreatorKernel

/// Merge: joins up to four inputs into one flat list, `a` first, then `b`, `c` and `d`. An input takes one wire, so
/// this is how different shapes reach a list socket such as Union's `shapes`. A single value is one item, a list
/// contributes its items, a tree its items row by row, and a culled list its survivors in order; the result is
/// renumbered, never culled. Unwired inputs are skipped. For more than four, merge a Merge.
public enum MergeNode: NodeDefinition {
    public static let typeID = "creator.merge"
    public static let displayName = "Merge"
    public static let librarySubgroup: String? = "Reshape"
    public static let category = NodeCategory.lists
    private static let names: [SocketName] = ["a", "b", "c", "d"]
    public static let inputs = names.map { SocketSpec($0, .any, access: .tree, optional: true) }
    public static let outputs = [SocketSpec("list", .any)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var items: [Scalar] = []
        for name in names where inputs.has(name) {
            items += try inputs.tree(name).items
        }
        return NodeOutputs(trees: ["list": .list(items)])
    }
}
