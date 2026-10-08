import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A point or direction from three numbers (spec §7.1, Values). Wired into a plane socket it
/// becomes the XY plane through the point (spec §4.2).
public enum VectorNode: NodeDefinition {
    public static let typeID = "creator.vector"
    public static let displayName = "Vector"
    public static let category = NodeCategory.value
    public static let inputs = [
        SocketSpec("x", .number, defaultValue: .number(0), unit: .millimetres),
        SocketSpec("y", .number, defaultValue: .number(0), unit: .millimetres),
        SocketSpec("z", .number, defaultValue: .number(0), unit: .millimetres),
    ]
    public static let outputs = [SocketSpec("vector", .vector)]
    public static let inspector = [InspectorSection(title: "Vector", controls: [.number("x"), .number("y"), .number("z")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let vector = Vector3(try inputs.number("x"), try inputs.number("y"), try inputs.number("z"))
        return NodeOutputs(["vector": .vector(vector)])
    }
}
