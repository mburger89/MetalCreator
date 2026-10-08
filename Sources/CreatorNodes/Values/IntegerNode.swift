import CreatorGraph
import CreatorKernel

/// A constant whole number (spec §7.1, Values).
public enum IntegerNode: NodeDefinition {
    public static let typeID = "creator.integer"
    public static let displayName = "Integer"
    public static let category = NodeCategory.value
    public static let inputs = [SocketSpec("value", .integer, defaultValue: .integer(0), unit: .count)]
    public static let outputs = [SocketSpec("value", .integer)]
    public static let inspector = [InspectorSection(title: "Value", controls: [.integer("value")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .integer(try inputs.integer("value"))])
    }
}
