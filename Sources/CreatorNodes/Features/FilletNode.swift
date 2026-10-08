import CreatorGraph
import CreatorKernel

/// Rounds the edges of an edge set with a constant radius (spec §7.1, Features; §6.4–6.5).
/// The edge set carries its solid, so there is no separate solid input. OCCT always follows
/// tangent chains, so the spec's "Tangent chain" toggle is not offered (M3 plan decision).
public enum FilletNode: NodeDefinition {
    public static let typeID = "creator.fillet"
    public static let displayName = "Fillet"
    public static let category = NodeCategory.feature
    public static let inputs = [
        SocketSpec("edges", .edgeSet),
        SocketSpec("radius", .number, defaultValue: .number(1), unit: .millimetres, range: 0.1...20),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    public static let inspector = [
        InspectorSection(title: "Fillet", controls: [.slider("radius"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges", controls: [.ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView)]),
    ]
    public static let handles = [HandleSpec.radial("radius")]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let set = try inputs.edgeSet("edges")
        let solid = try await kernel.fillet(set.solid, edges: set.edges, radius: try inputs.number("radius"), tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}
