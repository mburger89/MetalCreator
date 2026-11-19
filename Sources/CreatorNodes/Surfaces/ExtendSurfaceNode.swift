import CreatorGraph
import CreatorKernel

/// A sheet of one face grown across its picked open edges (NURBS spec, NS-4, R8): Natural continues the surface itself, curvature
/// continuous with it, Linear runs straight along the cross tangent. The face keeps its names and edges, so picks downstream survive.
public enum ExtendSurfaceNode: NodeDefinition {
    public static let typeID = "creator.extendSurface"
    public static let displayName = "Extend Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    /// The choices of `mode`, in option order.
    public static let modeOptions = ["Natural", "Linear"]
    public static let inputs = [
        SocketSpec("edges", .edgeSet),
        SocketSpec("length", .number, defaultValue: .number(5), unit: .millimetres, range: 0.001...10_000),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Extend Surface", controls: [.slider("length"), .segmented("mode", options: modeOptions)]),
        InspectorSection(title: "Edges", controls: [
            .ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let set = try inputs.edgeSet("edges")
        let mode: ExtendMode = try inputs.choice("mode", options: modeOptions) == 1 ? .linear : .natural
        let surface = try await kernel.extended(set.solid, edges: set.edges, length: try inputs.number("length"), mode: mode)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
