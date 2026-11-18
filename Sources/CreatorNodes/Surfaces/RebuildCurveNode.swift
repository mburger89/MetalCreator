import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A curve rebuilt as one spline piece of a chosen degree and number of spans: Rebuild Surface's twin (NURBS spec, control points).
public enum RebuildCurveNode: NodeDefinition {
    public static let typeID = "creator.rebuildCurve"
    public static let displayName = "Rebuild Curve"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let factsTitle = "Curve"
    public static let inputs = [
        SocketSpec("curve", .curve),
        SocketSpec("degree", .integer, defaultValue: .integer(3), range: 1...11),
        SocketSpec("spans", .integer, defaultValue: .integer(8), range: 1...1000),
        SocketSpec("tolerance", .number, defaultValue: .number(0.01), unit: .millimetres, range: 0.0001...1),
    ]
    public static let outputs = [SocketSpec("curve", .curve)]
    public static let inspector = [InspectorSection(title: "Rebuild", controls: [
        .integer("degree"), .integer("spans"), .slider("tolerance"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .curve(let curve) = try inputs.scalar("curve") else {
            throw NodeError.invalidValue("Rebuild Curve needs a curve; Profile to Curves makes one from a profile.")
        }
        let spec = RebuildSpec(degreeU: try inputs.integer("degree"), degreeV: 1, spansU: try inputs.integer("spans"), spansV: 1)
        let rebuilt = try await kernel.rebuilt(curve, as: spec, tag: context.tag)
        let net = try await kernel.controlNet(of: rebuilt.curve)
        let tolerance = try inputs.number("tolerance")
        var outputs = NodeOutputs(["curve": .curve(rebuilt.curve)],
                                  warnings: RebuildWording.warning(of: "curve", deviation: rebuilt.deviation, tolerance: tolerance))
        outputs.facts = ControlNetFacts.curve(net.curve, kind: nil) + [RebuildWording.fact(rebuilt.deviation)]
        return outputs
    }
}
