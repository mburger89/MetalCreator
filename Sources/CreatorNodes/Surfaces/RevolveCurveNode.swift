import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A curve turned about an axis into a sheet (NURBS spec). 360 degrees is a full turn.
public enum RevolveCurveNode: NodeDefinition {
    public static let typeID = "creator.revolveCurve"
    public static let displayName = "Revolve Curve"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let inputs = [
        SocketSpec("curve", .curve),
        SocketSpec("axis origin", .vector, defaultValue: .vector(.zero), unit: .millimetres),
        SocketSpec("axis direction", .vector, defaultValue: .vector(Vector3(0, 1, 0))),
        SocketSpec("angle", .number, defaultValue: .number(360), unit: .degrees, range: 1...360),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Revolve Curve", controls: [.slider("angle")]),
        InspectorSection(title: "Axis", controls: [.vector("axis origin"), .vector("axis direction")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let curves = try await CurveInput.loops(try inputs.curves("curve"), holes: .all, kernel: kernel, tag: context.tag)
        guard let curve = curves.first, curves.count == 1 else {
            throw NodeError.invalidValue("Revolve Curve takes one curve.")
        }
        let axis = Axis(origin: try inputs.vector("axis origin"), direction: try inputs.vector("axis direction"))
        let surface = try await kernel.revolve(curve, axis: axis, angle: .degrees(try inputs.number("angle")), tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
