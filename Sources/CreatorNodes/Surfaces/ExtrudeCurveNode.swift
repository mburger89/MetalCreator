import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A curve moved along a direction into a sheet (NURBS spec).
public enum ExtrudeCurveNode: NodeDefinition {
    public static let typeID = "creator.extrudeCurve"
    public static let displayName = "Extrude Curve"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let inputs = [
        SocketSpec("curve", .curve),
        SocketSpec("direction", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0.001...10_000),
        SocketSpec("symmetric", .bool, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [InspectorSection(title: "Extrude Curve", controls: [
        .vector("direction"), .slider("distance"), .toggle("symmetric", label: "Symmetric"),
    ]),
    ]
    public static let handles = [HandleSpec.linear("distance")]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let curves = try await CurveInput.loops(try inputs.curves("curve"), holes: .all, kernel: kernel, tag: context.tag)
        guard let curve = curves.first, curves.count == 1 else {
            throw NodeError.invalidValue("Extrude Curve takes one curve.")
        }
        let surface = try await kernel.extrude(curve, direction: try inputs.vector("direction"), distance: try inputs.number("distance"),
                                               symmetric: try inputs.bool("symmetric"), tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
