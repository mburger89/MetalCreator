import CreatorGraph
import CreatorKernel

/// Holds a field between two numbers (fields spec §3.2). A `low` above `high` fails; equal ends make the field constant.
public enum FieldClampNode: NodeDefinition {
    public static let typeID = "creator.fieldClamp"
    public static let displayName = "Clamp"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("field", .field, defaultValue: .number(0)),
        SocketSpec("low", .number, defaultValue: .number(0)),
        SocketSpec("high", .number, defaultValue: .number(1)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Limits", controls: [.number("low"), .number("high")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let field = try inputs.field("field")
        let (low, high) = (try inputs.number("low"), try inputs.number("high"))
        guard low.isFinite, high.isFinite else { throw NodeError.invalidValue("Clamp's limits must be finite numbers.") }
        guard low <= high else {
            throw NodeError.invalidValue("Clamp's low end (\(low.display)) is above its high end (\(high.display)).")
        }
        return NodeOutputs(["field": .field(.clamp(field, low: low, high: high))])
    }
}
