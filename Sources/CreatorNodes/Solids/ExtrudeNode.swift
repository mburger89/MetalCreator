import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Sweeps a closed profile along its plane's normal (spec §7.1, Solids; §6.4 inspector).
/// "Reverse direction" extrudes into −normal by starting the sweep `distance` behind the plane,
/// so the end cap then lies on the profile plane. It has no effect on a symmetric extrude.
public enum ExtrudeNode: NodeDefinition {
    public static let typeID = "creator.extrude"
    public static let displayName = "Extrude"
    public static let category = NodeCategory.solid
    public static let modes = ["One side", "Symmetric"]
    public static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("reversed", .bool, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [InspectorSection(title: "Extrude", controls: [
        .segmented("mode", options: modes), .slider("distance"), .toggle("reversed", label: "Reverse direction"),
    ]),
    ]
    public static let handles = [HandleSpec.linear("distance")]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var profile = try inputs.profile("profile")
        let distance = try inputs.number("distance")
        guard distance.isFinite, distance > 0 else {
            throw NodeError.invalidValue("Extrude distance must be greater than 0 mm.")
        }
        let mode: ExtrudeMode = try inputs.choice("mode", options: modes) == 0 ? .oneSided : .symmetric
        if mode == .oneSided, try inputs.bool("reversed") {
            profile.plane = profile.plane.offset(by: -distance)
        }
        let solid = try await kernel.extrude(profile, distance: distance, mode: mode, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
