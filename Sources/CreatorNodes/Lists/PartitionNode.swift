import CreatorGraph
import CreatorKernel

/// Splits every branch into branches of `size` items (7a spec §4), one level deeper; the last of each is shorter when
/// the count doesn't divide. A list of 24 with size 8 becomes 3 × 8, which is how a flat list becomes rows.
public enum PartitionNode: NodeDefinition {
    public static let typeID = "creator.partition"
    public static let displayName = "Partition"
    public static let category = NodeCategory.lists
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("size", .integer, defaultValue: .integer(2), unit: .count),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let inspector = [InspectorSection(title: "Partition", controls: [.integer("size")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let size = try inputs.integer("size")
        guard size >= 1 else { throw NodeError.invalidValue("“size” must be at least 1.") }
        return NodeOutputs(trees: ["tree": try inputs.tree("tree").partitioned(size: size)])
    }
}
