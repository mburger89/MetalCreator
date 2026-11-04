import CreatorGraph
import CreatorKernel

/// Converts a plain number between lengths (mm, cm, m, in, ft) or angles (deg, rad). Its `value` has no unit, so the
/// document's display units never touch it; a length input elsewhere reads millimetres, so convert to mm before wiring in.
public enum ConvertUnitsNode: NodeDefinition {
    public static let typeID = "creator.convertUnits"
    public static let displayName = "Convert Units"
    public static let category = NodeCategory.value
    public static let inputs = [
        SocketSpec("value", .number, defaultValue: .number(1)),
        SocketSpec("quantity", .integer, defaultValue: .integer(ConversionQuantity.length.rawValue)),
        SocketSpec("fromLength", .integer, defaultValue: .integer(ConversionLength.inches.rawValue)),
        SocketSpec("toLength", .integer, defaultValue: .integer(ConversionLength.millimetres.rawValue)),
        SocketSpec("fromAngle", .integer, defaultValue: .integer(ConversionAngle.degrees.rawValue)),
        SocketSpec("toAngle", .integer, defaultValue: .integer(ConversionAngle.radians.rawValue)),
    ]
    public static let outputs = [SocketSpec("value", .number)]
    static let note = "Length inputs elsewhere read millimetres, so convert to mm before wiring into one."

    private static let head: [InspectorControl] = [.number("value"), .segmented("quantity", options: ConversionQuantity.options)]
    /// The converted number, so the node says what it makes (25.4 for 1 in to mm).
    private static let result: [InspectorControl] = [.result("value")]
    private static let lengthControls: [InspectorControl] = [
        .segmented("fromLength", options: ConversionLength.options), .segmented("toLength", options: ConversionLength.options),
    ]
    private static let angleControls: [InspectorControl] = [
        .segmented("fromAngle", options: ConversionAngle.options), .segmented("toAngle", options: ConversionAngle.options),
    ]

    /// Every control, for the catalogue; the editor asks `inspector(for:)`.
    public static let inspector = [InspectorSection(title: "Convert", controls: head + lengthControls + angleControls + result + [.note(note)])]

    /// Only the active quantity's two controls.
    public static func inspector(for node: Node) -> [InspectorSection] {
        let angle = node.inputValues["quantity"] == .integer(ConversionQuantity.angle.rawValue)
        return [InspectorSection(title: "Convert", controls: head + (angle ? angleControls : lengthControls) + result + [.note(note)])]
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let value = try inputs.number("value")
        let quantity = ConversionQuantity(rawValue: try inputs.choice("quantity", options: ConversionQuantity.options)) ?? .length
        let (from, to): (Double, Double)
        let same: Bool
        switch quantity {
        case .length:
            let (a, b) = (try inputs.choice("fromLength", options: ConversionLength.options),
                          try inputs.choice("toLength", options: ConversionLength.options))
            (from, to, same) = (ConversionLength(rawValue: a)?.millimetres ?? 1, ConversionLength(rawValue: b)?.millimetres ?? 1, a == b)
        case .angle:
            let (a, b) = (try inputs.choice("fromAngle", options: ConversionAngle.options),
                          try inputs.choice("toAngle", options: ConversionAngle.options))
            (from, to, same) = (ConversionAngle(rawValue: a)?.radians ?? 1, ConversionAngle(rawValue: b)?.radians ?? 1, a == b)
        }
        let result = same ? value : value * from / to
        guard value.isFinite, result.isFinite else { throw NodeError.invalidValue("“value” must be a finite number.") }
        return NodeOutputs(["value": .number(result)])
    }
}
