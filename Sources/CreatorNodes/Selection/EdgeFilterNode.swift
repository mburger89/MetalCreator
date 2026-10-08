import CreatorGraph
import CreatorKernel

/// Edges by convexity and length (spec §7.1, Selection). `maxLength` is optional: unset means
/// no upper limit. Smooth (tangent) edges count only under "Any".
public enum EdgeFilterNode: NodeDefinition {
    public static let typeID = "creator.edgeFilter"
    public static let displayName = "Edge Filter"
    public static let category = NodeCategory.selection
    public static let convexities = ["Any", "Convex", "Concave"]
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("convexity", .integer, defaultValue: .integer(0)),
        SocketSpec("minLength", .number, defaultValue: .number(0), unit: .millimetres),
        SocketSpec("maxLength", .number, unit: .millimetres, optional: true),
    ]
    public static let outputs = [SocketSpec("edges", .edgeSet)]
    public static let inspector = [InspectorSection(title: "Filter", controls: [
        .segmented("convexity", options: convexities), .number("minLength"), .number("maxLength"), .ruleSummary("edges"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let wanted: Convexity? = [nil, .convex, .concave][try inputs.choice("convexity", options: convexities)]
        let minimum = try inputs.number("minLength")
        let maximum = inputs.has("maxLength") ? try inputs.number("maxLength") : .infinity
        guard minimum <= maximum else {
            throw NodeError.invalidValue("“minLength” (\(minimum.display) mm) is more than “maxLength” (\(maximum.display) mm).")
        }
        let tolerance = 1e-6
        let matches = EdgeSelection.candidates(solid).filter { edge in
            (wanted == nil || edge.convexity == wanted)
                && edge.length >= minimum - tolerance && edge.length <= maximum + tolerance
        }
        return EdgeSelection.outputs(solid, matches.map(\.id))
    }
}
