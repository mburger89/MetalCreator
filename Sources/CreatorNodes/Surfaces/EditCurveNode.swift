import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A one-piece curve with some of its control points moved: Edit Surface's twin (NURBS spec, control points). The ends are poles
/// like the rest, so moving one moves the curve's end.
public enum EditCurveNode: NodeDefinition {
    public static let typeID = "creator.editCurve"
    public static let displayName = "Edit Curve"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let factsTitle = "Curve"
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.poleMoves: .poleMoves([])]
    public static let inputs = [SocketSpec("curve", .curve)]
    public static let outputs = [SocketSpec("curve", .curve)]
    public static let inspector = [InspectorSection(title: "Edit Curve", controls: [
        .button(title: "Edit Control Points", action: .editControlPoints),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .curve(let curve) = try inputs.scalar("curve") else {
            throw NodeError.invalidValue("Edit Curve needs a curve; Profile to Curves makes one from a profile.")
        }
        let net = try await kernel.controlNet(of: curve)
        let moves = context.node.inputValues[NodeSetting.poleMoves]?.poleMoves ?? []
        let count = net.curve.poles.count
        let fitting = moves.filter { $0.index.i < count && $0.index.j == 0 }
        var warnings: [String] = []
        if fitting.count < moves.count {
            let place = "the curve's \(count.display) control points"
            warnings.append(ControlNetFacts.staleWarning(count: moves.count - fitting.count, place: place))
        }
        let result = fitting.isEmpty ? curve : try await kernel.movingPoles(of: curve, by: fitting)
        var outputs = NodeOutputs(["curve": .curve(result)], warnings: warnings)
        outputs.facts = ControlNetFacts.curve(net.curve, kind: net.convertedFrom)
        return outputs
    }
}
