import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A field that grows along a plane's normal (fields spec §3.1): 0 on the plane, 1 one `length` along the normal, unclamped,
/// negative behind it.
public enum LinearGradientNode: NodeDefinition {
    public static let typeID = "creator.linearGradient"
    public static let displayName = "Linear Gradient"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("length", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...1000),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Gradient", controls: [.planePicker("plane"), .slider("length")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let plane = try inputs.plane("plane")
        let length = try inputs.number("length")
        guard length.isFinite, length > 0 else { throw NodeError.invalidValue("“length” must be greater than 0 mm.") }
        guard plane.origin.isFinite, let normal = plane.normal.normalized else {
            throw NodeError.invalidValue("“plane” has no direction.")
        }
        let unit = Plane(origin: plane.origin, normal: normal, xAxis: plane.xAxis)
        return NodeOutputs(["field": .field(.linearGradient(plane: unit, length: length))])
    }
}
