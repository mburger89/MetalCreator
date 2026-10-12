import CreatorGraph
import CreatorKernel
import Foundation

/// A random number for every instance (patterns spec §4), reals or whole numbers in a range, in the shape of a tree wired
/// into `shape` or, with nothing wired, a flat list of `count`. Wire `values` into a size (diameters, heights) or `integers`
/// into a count or a Cull Index to vary a pattern. It is always seeded (`SeededRandom`, SplitMix64, purpose `.values`): the same
/// seed gives the same numbers on every machine and in every release, and not the numbers Random Reduce or Jitter draw for it. A number depends on the seed and on where its item is (its branch's
/// ordinal and its index in the branch), never on how many items there are, so more instances or a cull don't change the
/// numbers the others get, and a shape that was culled gets numbers at the paths it kept. A new seed never warns.
///
/// `values` are reals from `min` up to `max`. `integers` are whole numbers from `min` rounded up to `max` rounded down,
/// both ends included; there are none (and the output is left out) when no whole number lies between them.
public enum RandomValuesNode: NodeDefinition {
    public static let typeID = "creator.randomValues"
    public static let displayName = "Random Values"
    public static let category = NodeCategory.patterns
    /// The most numbers made from a count, so a typo gives a message instead of a hang.
    public static let maximumCount = 100_000
    public static let inputs = [
        SocketSpec("shape", .any, access: .tree, optional: true),
        SocketSpec("count", .integer, defaultValue: .integer(8), unit: .count),
        SocketSpec("min", .number, defaultValue: .number(0)),
        SocketSpec("max", .number, defaultValue: .number(1)),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("values", .number), SocketSpec("integers", .integer, optional: true)]
    public static let inspector = [
        InspectorSection(title: "Range", controls: [.number("min"), .number("max")]),
        InspectorSection(title: "Random", controls: [.integer("count"), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (low, high) = (try inputs.number("min"), try inputs.number("max"))
        guard low.isFinite, high.isFinite else { throw NodeError.invalidValue("“min” and “max” must be numbers.") }
        guard low <= high else { throw NodeError.invalidValue("“min” can't be more than “max”.") }
        let seed = try inputs.integer("seed")
        let shape = try shape(of: inputs)
        let reals = shape.mappingItems { leaf, ordinal, k in
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .values)
            return .number(low + random.unit(at: leaf.positions[k]) * (high - low))
        }
        var trees: [SocketName: DataTree] = ["values": reals]
        let (first, last) = (low.rounded(.up), high.rounded(.down))
        if first <= last, abs(first) < 1e15, abs(last) < 1e15 {
            let (lowest, span) = (Int(first), Int(last - first) + 1)
            trees["integers"] = shape.mappingItems { leaf, ordinal, k in
                .integer(lowest + SeededRandom(seed: seed, stream: ordinal, purpose: .values).below(span, at: leaf.positions[k]))
            }
        }
        return NodeOutputs(trees: trees)
    }

    /// The tree to fill: the wired shape, or a flat list of `count` placeholders.
    private static func shape(of inputs: NodeInputs) throws -> DataTree {
        if inputs.has("shape") { return try inputs.tree("shape") }
        let count = try inputs.integer("count")
        guard count >= 0 else { throw NodeError.invalidValue("“count” can't be negative.") }
        guard count <= maximumCount else {
            throw NodeError.invalidValue("Random Values makes at most \(maximumCount.display) numbers.")
        }
        return .list(Array(repeating: .integer(0), count: count))
    }
}
