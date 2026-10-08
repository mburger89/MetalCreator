import CreatorGraph
import CreatorKernel

/// Bevels the edges of an edge set by an equal distance on both faces (spec §7.1, Features).
public enum ChamferNode: NodeDefinition {
    public static let typeID = "creator.chamfer"
    public static let displayName = "Chamfer"
    public static let category = NodeCategory.feature
    public static let inputs = [
        SocketSpec("edges", .edgeSet),
        SocketSpec("distance", .number, defaultValue: .number(0.5), unit: .millimetres, range: 0.1...10),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    public static let inspector = [
        InspectorSection(title: "Chamfer", controls: [.slider("distance"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges", controls: [
            .ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView),
        ]),
    ]
    public static let handles = [HandleSpec.radial("distance")]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let set = try inputs.edgeSet("edges")
        let solid = try await kernel.chamfer(set.solid, edges: set.edges, distance: try inputs.number("distance"), tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
