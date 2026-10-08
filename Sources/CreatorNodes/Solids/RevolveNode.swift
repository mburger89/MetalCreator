import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Turns a closed profile about an axis in model space (spec §7.1, Solids). 360° is a full turn.
public enum RevolveNode: NodeDefinition {
    public static let typeID = "creator.revolve"
    public static let displayName = "Revolve"
    public static let category = NodeCategory.solid
    public static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("axisOrigin", .vector, defaultValue: .vector(.zero), unit: .millimetres),
        SocketSpec("axisDirection", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("angle", .number, defaultValue: .number(360), unit: .degrees, range: 1...360),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Revolve", controls: [.slider("angle")]),
        InspectorSection(title: "Axis", controls: [.vector("axisOrigin"), .vector("axisDirection")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let axis = Axis(origin: try inputs.vector("axisOrigin"), direction: try inputs.vector("axisDirection"))
        let solid = try await kernel.revolve(try inputs.profile("profile"), axis: axis,
                                             angle: .degrees(try inputs.number("angle")), tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
