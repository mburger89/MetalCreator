import CreatorGraph
import CreatorKernel

/// Maps a field's range onto another (fields spec §3.2): `fromLow…fromHigh` onto `toLow…toHigh`, linearly, and held to the
/// output range while `clamp` is on. The ends may run either way (`0…20 → 1…0` fades out). Equal from ends can't be mapped
/// and fail with a message.
public enum FieldRemapNode: NodeDefinition {
    public static let typeID = "creator.fieldRemap"
    public static let displayName = "Remap"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("field", .field, defaultValue: .number(0)),
        SocketSpec("fromLow", .number, defaultValue: .number(0)),
        SocketSpec("fromHigh", .number, defaultValue: .number(1)),
        SocketSpec("toLow", .number, defaultValue: .number(0)),
        SocketSpec("toHigh", .number, defaultValue: .number(1)),
        SocketSpec("clamp", .bool, defaultValue: .bool(true)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [
        InspectorSection(title: "From", controls: [.number("fromLow"), .number("fromHigh")]),
        InspectorSection(title: "To", controls: [.number("toLow"), .number("toHigh")]),
        InspectorSection(title: "Limits", controls: [.toggle("clamp", label: "Clamp to the output range")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let field = try inputs.field("field")
        let (fromLow, fromHigh) = (try inputs.number("fromLow"), try inputs.number("fromHigh"))
        let (toLow, toHigh) = (try inputs.number("toLow"), try inputs.number("toHigh"))
        guard [fromLow, fromHigh, toLow, toHigh].allSatisfy(\.isFinite) else {
            throw NodeError.invalidValue("Remap's ranges must be finite numbers.")
        }
        guard fromLow != fromHigh else {
            throw NodeError.invalidValue("Remap's from range is empty (both ends are \(fromLow.display)).")
        }
        let mapped = Field.remap(field, fromLow: fromLow, fromHigh: fromHigh, toLow: toLow, toHigh: toHigh,
                                 clamped: try inputs.bool("clamp"))
        return NodeOutputs(["field": .field(mapped)])
    }
}
