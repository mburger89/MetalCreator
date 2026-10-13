import CreatorGraph
import CreatorKernel

/// The lower or the higher of two fields at each point (fields spec §3.2).
public enum FieldMinMaxNode: NodeDefinition {
    public static let typeID = "creator.fieldMinMax"
    public static let displayName = "Min / Max"
    public static let category = NodeCategory.fields
    public static let modes = ["Min", "Max"]
    public static let inputs = [
        SocketSpec("a", .field, defaultValue: .number(0)),
        SocketSpec("b", .field, defaultValue: .number(0)),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [
        InspectorSection(title: "Fields", controls: [.number("a"), .number("b")]),
        InspectorSection(title: "Pick", controls: [.segmented("mode", options: modes)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (a, b) = (try inputs.field("a"), try inputs.field("b"))
        let picksMax = try inputs.choice("mode", options: modes) == 1
        return NodeOutputs(["field": .field(picksMax ? .maximum(a, b) : .minimum(a, b))])
    }
}
