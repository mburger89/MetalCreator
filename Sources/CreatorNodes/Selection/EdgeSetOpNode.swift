import CreatorGraph
import CreatorKernel

/// Combines two edge sets of the same solid (spec §7.1, Selection). The result has no
/// duplicates and keeps `a`'s order, then `b`'s. "Same solid" is the same instance, or equal
/// topology and bounds: when the LRU cache evicts the upstream solid and one rule but keeps the
/// other, the recomputed rule holds a new instance of an identical solid (OCCT's face and edge
/// IDs are deterministic map order). Face tags carry node IDs, so solids from different nodes
/// never compare equal.
public enum EdgeSetOpNode: NodeDefinition {
    public static let typeID = "creator.edgeSetOp"
    public static let displayName = "Edge Set Op"
    public static let category = NodeCategory.selection
    public static let operations = ["Union", "Subtract", "Intersect"]
    public static let inputs = [
        SocketSpec("a", .edgeSet),
        SocketSpec("b", .edgeSet),
        SocketSpec("operation", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("edges", .edgeSet)]
    public static let inspector = [InspectorSection(title: "Combine", controls: [
        .segmented("operation", options: operations), .ruleSummary("edges"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (a, b) = (try inputs.edgeSet("a"), try inputs.edgeSet("b"))
        guard a.solid === b.solid || (a.solid.topology == b.solid.topology && a.solid.bounds == b.solid.bounds) else {
            throw NodeError.invalidValue("Both edge sets must select edges of the same solid. Wire both rules from the same node.")
        }
        let inB = Set(b.edges)
        var seen: Set<EdgeID> = []
        let combined: [EdgeID] = switch try inputs.choice("operation", options: operations) {
        case 0: a.edges + b.edges
        case 1: a.edges.filter { !inB.contains($0) }
        default: a.edges.filter { inB.contains($0) }
        }
        return EdgeSelection.outputs(a.solid, combined.filter { seen.insert($0).inserted })
    }
}
