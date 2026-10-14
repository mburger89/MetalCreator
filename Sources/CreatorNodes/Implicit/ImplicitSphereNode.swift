import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A ball about the origin as an implicit solid (implicit spec §3.2): exact distance, lipschitz 1. Place moves it.
public enum ImplicitSphereNode: NodeDefinition {
    public static let typeID = "creator.implicitSphere"
    public static let displayName = "Sphere"
    public static let category = NodeCategory.implicit
    public static let inputs = [SocketSpec("radius", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...1000)]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "Sphere", controls: [.slider("radius")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let radius = try inputs.number("radius")
        guard radius.isFinite, radius > 0 else { throw NodeError.invalidValue("“radius” must be greater than 0 mm.") }
        return NodeOutputs(["implicit": .implicit(ImplicitSolid.sphere(radius: radius).reference)])
    }
}
