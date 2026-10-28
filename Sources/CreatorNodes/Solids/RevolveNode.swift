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
        let profile = try inputs.profile("profile")
        let degrees = try inputs.number("angle")
        let solid = try await kernel.revolve(profile, axis: axis, angle: .degrees(degrees), tag: context.tag)
        var outputs = NodeOutputs(["solid": .solid(solid)])
        outputs.dimensions = dimensions(profile: profile, axis: axis, degrees: degrees)
        return outputs
    }

    /// The angle swept, from the profile's centre about the axis; a full turn has nothing to dimension.
    private static func dimensions(profile: Profile2D, axis: Axis, degrees: Double) -> [DimensionSpec] {
        guard degrees < 360, let bounds = DimensionSpecs.planeBounds(of: profile),
              let direction = axis.direction.normalized else { return [] }
        let centre = profile.plane.point(Vector2((bounds.min.x + bounds.max.x) / 2, (bounds.min.y + bounds.max.y) / 2))
        let relative = centre - axis.origin
        let vertex = axis.origin + direction * relative.dot(direction)
        let second = axis.origin + relative.rotated(about: direction, by: .degrees(degrees))
        let geometry = DimensionGeometry.angular(vertex: vertex, first: centre, second: second, normal: direction, placement: .standoff)
        return [DimensionSpec(.input("angle"), geometry, .angle, value: degrees)]
    }
}
