import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Shakes placements a little (patterns spec §4): each one moves a random distance in its own plane, up to `distance`, and
/// turns a random angle about its own normal, up to `turn` either way. Wire the result into Place or a shortcut for a pattern
/// that looks hand-placed. It is always seeded (`SeededRandom`, SplitMix64, purpose `.jitter`, `PlaneJitter`): the same seed gives the same
/// placements on every machine and in every release, a placement's move depends on the seed and its place alone (so more
/// placements, or a cull, don't move the others), and a new seed never warns. Culling keeps paths: a culled input stays
/// culled, with the same indices.
public enum JitterNode: NodeDefinition {
    public static let typeID = "creator.jitter"
    public static let displayName = "Jitter"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("distance", .number, defaultValue: .number(1), unit: .millimetres, range: 0...50),
        SocketSpec("turn", .number, defaultValue: .number(5), unit: .degrees, range: 0...180),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [
        InspectorSection(title: "Jitter", controls: [.slider("distance"), .slider("turn"), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("placements")
        guard tree.items.allSatisfy({ $0.type == .plane }) else { throw NodeError.typeMismatch("placements", expected: .plane) }
        let (distance, turn) = (try inputs.number("distance"), try inputs.number("turn"))
        guard distance.isFinite, distance >= 0 else { throw NodeError.invalidValue("“distance” can't be negative.") }
        guard turn.isFinite, turn >= 0 else { throw NodeError.invalidValue("“turn” can't be negative.") }
        let seed = try inputs.integer("seed")
        let shaken = tree.mappingItems { leaf, ordinal, k in
            guard case .plane(let plane) = leaf.items[k] else { return leaf.items[k] }
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .jitter)
            return .plane(PlaneJitter.jittered(plane, random: random, index: leaf.positions[k], distance: distance, turn: turn))
        }
        return NodeOutputs(trees: ["placements": shaken])
    }
}
