import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Rotates a solid about an axis, then moves it (spec §7.1, Solids). A rotation needs an axis:
/// `axisDirection` has no default, so a non-zero angle without one is an error rather than a
/// guess. Broadcasting `move` over a point list makes one copy per point.
public enum TransformNode: NodeDefinition {
    public static let typeID = "creator.transform"
    public static let displayName = "Transform"
    public static let category = NodeCategory.solid
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("move", .vector, defaultValue: .vector(.zero), unit: .millimetres),
        SocketSpec("angle", .number, defaultValue: .number(0), unit: .degrees, range: -360...360),
        SocketSpec("axisOrigin", .vector, defaultValue: .vector(.zero), unit: .millimetres),
        SocketSpec("axisDirection", .vector, optional: true),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Move", controls: [.vector("move")]),
        InspectorSection(title: "Rotate", controls: [.slider("angle"), .vector("axisOrigin"), .vector("axisDirection")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let angle = try inputs.number("angle")
        var axis: Axis?
        if inputs.has("axisDirection") {
            let direction = try inputs.vector("axisDirection")
            guard direction.normalized != nil else { throw NodeError.invalidValue("The rotation axis direction can't be zero.") }
            axis = Axis(origin: try inputs.vector("axisOrigin"), direction: direction)
        }
        guard angle == 0 || axis != nil else {
            throw NodeError.invalidValue("Set “axisDirection” to rotate by \(angle.display)°.")
        }
        let transform = Transform(translation: try inputs.vector("move"), rotationAxis: axis, rotation: .degrees(angle))
        let solid = try await kernel.transform(try inputs.solid("solid"), by: transform, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
