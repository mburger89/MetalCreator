import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Keeps placements where a field says (fields spec §3.3), returning the same nesting with a culled list where items went, so
/// instance picks survive as with the other cull nodes (patterns spec §4 and §6).
/// - Threshold: Above keeps a placement whose field is at least `level`, Below one whose field is at most `level`.
/// - Probability: keeps a placement when a `SeededRandom` draw is below the field held to 0…1. The draw is the item's kept
///   index in the stream of its branch's ordinal, purpose `.fieldCull`, exactly how Random Reduce draws, so it depends on the
///   seed and the place alone and a cull before this node changes no survivor's draw.
public enum CullByFieldNode: NodeDefinition {
    public static let typeID = "creator.cullByField"
    public static let displayName = "Cull by Field"
    public static let category = NodeCategory.fields
    public static let modes = ["Threshold", "Probability"]
    public static let sides = ["Above", "Below"]
    public static let inputs = [
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("field", .field),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("level", .number, defaultValue: .number(0.5)),
        SocketSpec("keep", .integer, defaultValue: .integer(0)),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [
        InspectorSection(title: "Cull", controls: [.segmented("mode", options: modes)]),
        InspectorSection(title: "Threshold", controls: [.number("level"), .segmented("keep", options: sides)]),
        InspectorSection(title: "Probability", controls: [.integer("seed")]),
    ]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("placements")
        let origins = try tree.items.map { scalar -> Vector3 in
            guard case .plane(let plane) = scalar else { throw NodeError.typeMismatch("placements", expected: .plane) }
            return plane.origin
        }
        let byProbability = try inputs.choice("mode", options: modes) == 1
        let keepsAbove = try inputs.choice("keep", options: sides) == 0
        let (level, seed) = (try inputs.number("level"), try inputs.integer("seed"))
        let values = try await FieldSampler.sample(try inputs.field("field"), at: origins, kernel: kernel, cache: context.fieldDistances)

        // Where each branch's items start in `values`, and each branch's stream of draws.
        let leaves = tree.leaves
        var starts: [Int] = []
        var running = 0
        for leaf in leaves {
            starts.append(running)
            running += leaf.items.count
        }
        let draws = leaves.indices.map { SeededRandom(seed: seed, stream: $0, purpose: .fieldCull) }
        let kept = tree.keepingItems { leaf, ordinal, k in
            let value = values[starts[ordinal] + k]
            if byProbability { return draws[ordinal].unit(at: leaf.positions[k]) < min(max(value, 0), 1) }
            return keepsAbove ? value >= level : value <= level
        }
        return NodeOutputs(trees: ["placements": kept])
    }
}
