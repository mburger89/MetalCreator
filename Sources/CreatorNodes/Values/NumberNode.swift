import CreatorGraph
import CreatorKernel

/// A constant number (spec §7.1, Values).
public enum NumberNode: NodeDefinition {
    public static let typeID = "creator.number"
    public static let displayName = "Number"
    public static let category = NodeCategory.value
    public static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    public static let outputs = [SocketSpec("value", .number)]
    public static let inspector = [InspectorSection(title: "Value", controls: [.number("value")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}
