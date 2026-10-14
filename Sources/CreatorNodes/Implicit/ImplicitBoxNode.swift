import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A box about the origin as an implicit solid, with rounded edges if asked (implicit spec §3.2).
public enum ImplicitBoxNode: NodeDefinition {
    public static let typeID = "creator.implicitBox"
    public static let displayName = "Box"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("size", .vector, defaultValue: .vector(Vector3(20, 20, 20)), unit: .millimetres),
        SocketSpec("corner radius", .number, defaultValue: .number(0), unit: .millimetres, range: 0...50),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "Box", controls: [.vector("size"), .slider("corner radius")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let size = try inputs.vector("size")
        let radius = try inputs.number("corner radius")
        guard size.isFinite, size.x > 0, size.y > 0, size.z > 0 else {
            throw NodeError.invalidValue("“size” must be greater than 0 mm on every side.")
        }
        guard radius.isFinite, radius >= 0 else { throw NodeError.invalidValue("“corner radius” must be 0 or more.") }
        guard radius <= min(size.x, size.y, size.z) / 2 else {
            throw NodeError.invalidValue("“corner radius” can't be more than half the smallest side.")
        }
        return NodeOutputs(["implicit": .implicit(ImplicitSolid.box(halfSize: size * 0.5, cornerRadius: radius).reference)])
    }
}
