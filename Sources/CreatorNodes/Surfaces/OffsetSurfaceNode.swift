import CreatorGraph
import CreatorKernel

/// A sheet moved along its normals by a distance, a negative one against them (NS-5, R4, R7).
public enum OffsetSurfaceNode: NodeDefinition {
    public static let typeID = "creator.offsetSurface"
    public static let displayName = "Offset Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    public static let inputs = [
        SocketSpec("surface", .solid),
        SocketSpec("distance", .number, defaultValue: .number(1), unit: .millimetres, range: -100...100),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [InspectorSection(title: "Offset Surface", controls: [.slider("distance")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sheet = try await kernel.offsetSurface(try inputs.solid("surface"), distance: try inputs.number("distance"), tag: context.tag)
        return NodeOutputs(["surface": .solid(sheet)])
    }
}
