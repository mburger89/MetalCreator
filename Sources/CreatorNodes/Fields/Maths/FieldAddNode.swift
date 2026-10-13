import CreatorGraph
import CreatorKernel

/// a + b, where each is a field or a number (fields spec §3.2). A number typed or wired into either side is a constant field.
public enum FieldAddNode: NodeDefinition {
    public static let typeID = "creator.fieldAdd"
    public static let displayName = "Add"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("a", .field, defaultValue: .number(0)),
        SocketSpec("b", .field, defaultValue: .number(0)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Add", controls: [.number("a"), .number("b")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["field": .field(.add(try inputs.field("a"), try inputs.field("b")))])
    }
}
