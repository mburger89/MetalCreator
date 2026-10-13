import CreatorGraph
import CreatorKernel

/// a × b (fields spec §3.2). "Multiply by 0.5" is 0.5 typed into `b`.
public enum FieldMultiplyNode: NodeDefinition {
    public static let typeID = "creator.fieldMultiply"
    public static let displayName = "Multiply"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("a", .field, defaultValue: .number(1)),
        SocketSpec("b", .field, defaultValue: .number(1)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Multiply", controls: [.number("a"), .number("b")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["field": .field(.multiply(try inputs.field("a"), try inputs.field("b")))])
    }
}
