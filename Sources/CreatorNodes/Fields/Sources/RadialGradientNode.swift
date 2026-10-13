import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A field of the distance from a centre over a radius (fields spec §3.1): 0 at the centre, 1 at the radius, unclamped.
public enum RadialGradientNode: NodeDefinition {
    public static let typeID = "creator.radialGradient"
    public static let displayName = "Radial Gradient"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("center", .vector, defaultValue: .vector(.zero), unit: .millimetres),
        SocketSpec("radius", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...1000),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Gradient", controls: [.vector("center"), .slider("radius")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let center = try inputs.vector("center")
        let radius = try inputs.number("radius")
        guard radius.isFinite, radius > 0 else { throw NodeError.invalidValue("“radius” must be greater than 0 mm.") }
        guard center.isFinite else { throw NodeError.invalidValue("“center” isn't a finite position.") }
        return NodeOutputs(["field": .field(.radialGradient(center: center, radius: radius))])
    }
}
