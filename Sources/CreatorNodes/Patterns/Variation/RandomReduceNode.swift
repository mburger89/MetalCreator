import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Drops items at random (patterns spec §4): a count or a fraction, from the whole tree (the default) or from each branch.
/// Overall is the default because it does the same at every depth: per branch, a tree whose branches hold one item each (a
/// Face Pattern's `{row;column;0}` cells) loses every item (User decision U16). It is always
/// seeded: the same seed drops the same items on every machine and in every release (`SeededRandom`, SplitMix64), so an
/// edit elsewhere never reshuffles it, and a new seed is just a different draw, never a warning. Culling keeps paths: the
/// items that stay keep their indices, so a pick on one follows it (§6) and a pick on a dropped item warns naming its path.
public enum RandomReduceNode: NodeDefinition {
    public static let typeID = "creator.randomReduce"
    public static let displayName = "Random Reduce"
    public static let category = NodeCategory.patterns
    public static let amounts = ["Count", "Fraction"]
    public static let scopes = ["Per branch", "Overall"]
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("by", .integer, defaultValue: .integer(0)),
        SocketSpec("count", .integer, defaultValue: .integer(1), unit: .count),
        SocketSpec("fraction", .number, defaultValue: .number(0.25), range: 0...1),
        SocketSpec("scope", .integer, defaultValue: .integer(1)),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let inspector = [
        InspectorSection(title: "Drop", controls: [.segmented("by", options: amounts), .integer("count"), .slider("fraction")]),
        InspectorSection(title: "Random", controls: [.segmented("scope", options: scopes), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        let amount: RandomReduction.Amount
        if try inputs.choice("by", options: amounts) == 0 {
            let count = try inputs.integer("count")
            guard count >= 0 else { throw NodeError.invalidValue("“count” can't be negative.") }
            amount = .count(count)
        } else {
            let fraction = try inputs.number("fraction")
            guard fraction.isFinite, (0...1).contains(fraction) else {
                throw NodeError.invalidValue("“fraction” must be between 0 and 1: 0 drops nothing and 1 drops everything.")
            }
            amount = .fraction(fraction)
        }
        let overall = try inputs.choice("scope", options: scopes) == 1
        let dropped = RandomReduction.slotsToDrop(in: tree, seed: try inputs.integer("seed"), amount: amount, overall: overall)
        let kept = tree.keepingItems { _, ordinal, k in !dropped.contains(RandomReduction.Slot(ordinal: ordinal, k: k)) }
        return NodeOutputs(trees: ["tree": kept])
    }
}
