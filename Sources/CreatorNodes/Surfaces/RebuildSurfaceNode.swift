import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A sheet of one face rebuilt to a chosen degree and number of spans in each direction (NURBS spec, control points): the way to get
/// an even net to edit. The faces and names are the input's; `tolerance` is the distance the result may lie from the original before
/// the node warns, and the fact "Deviation" says how far it does.
public enum RebuildSurfaceNode: NodeDefinition {
    public static let typeID = "creator.rebuildSurface"
    public static let displayName = "Rebuild Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let factsTitle = "Surface"
    public static let inputs = [
        SocketSpec("surface", .solid),
        SocketSpec("degreeU", .integer, defaultValue: .integer(3), range: 1...11),
        SocketSpec("degreeV", .integer, defaultValue: .integer(3), range: 1...11),
        SocketSpec("spansU", .integer, defaultValue: .integer(4), range: 1...1000),
        SocketSpec("spansV", .integer, defaultValue: .integer(4), range: 1...1000),
        SocketSpec("tolerance", .number, defaultValue: .number(0.01), unit: .millimetres, range: 0.0001...1),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Direction U", controls: [.integer("degreeU"), .integer("spansU")]),
        InspectorSection(title: "Direction V", controls: [.integer("degreeV"), .integer("spansV")]),
        InspectorSection(title: "Fit", controls: [.slider("tolerance")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let surface = try inputs.solid("surface")
        let spec = RebuildSpec(degreeU: try inputs.integer("degreeU"), degreeV: try inputs.integer("degreeV"),
                               spansU: try inputs.integer("spansU"), spansV: try inputs.integer("spansV"))
        let rebuilt = try await kernel.rebuilt(surface, as: spec)
        let net = try await kernel.controlNet(of: rebuilt.sheet)
        let tolerance = try inputs.number("tolerance")
        var outputs = NodeOutputs(["surface": .solid(rebuilt.sheet)],
                                  warnings: RebuildWording.warning(of: "surface", deviation: rebuilt.deviation, tolerance: tolerance))
        outputs.facts = ControlNetFacts.surface(net.surface, kind: nil) + [RebuildWording.fact(rebuilt.deviation)]
        return outputs
    }
}

/// The sentences the two rebuild nodes share.
enum RebuildWording {
    /// "Deviation: 0.003 mm".
    static func fact(_ deviation: Double) -> PayloadFact { PayloadFact("Deviation", "\(length(deviation)) mm") }

    /// "The rebuilt surface is up to 0.12 mm from the original, more than the 0.01 mm tolerance." when the deviation is over
    /// the tolerance, else nothing.
    static func warning(of kind: String, deviation: Double, tolerance: Double) -> [String] {
        guard deviation > tolerance else { return [] }
        return ["The rebuilt \(kind) is up to \(length(deviation)) mm from the original, more than the \(length(tolerance)) mm tolerance."]
    }

    /// Small lengths keep their significant digits (0.003), larger ones two decimals.
    private static func length(_ value: Double) -> String {
        abs(value) < 1
            ? value.formatted(.number.precision(.significantDigits(1...2)).locale(.messages))
            : value.display
    }
}
