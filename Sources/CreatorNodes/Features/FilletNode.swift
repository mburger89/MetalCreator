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
        SocketSpec("continuity", .integer, defaultValue: .integer(0), range: 0...1),
        SocketSpec("tangency weight", .number, defaultValue: .number(1), range: 0.1...2),
    ]
    /// The choices of `continuity`, in option order.
    public static let continuityOptions = ["Tangent (G1)", "Curvature (G2)"]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    private static func sections(curvature: Bool) -> [InspectorSection] {
        let fillet: [InspectorControl] = [.slider("radius"), .segmented("continuity", options: continuityOptions)]
            + (curvature ? [.slider("tangency weight")] : [])
            + [.toggle(NodeSetting.showHandle, label: "Show handle in view")]
        return [
            InspectorSection(title: "Fillet", controls: fillet),
            InspectorSection(title: "Edges", controls: [
                .ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView),
            ]),
        ]
    }

    /// Every control, for a reader that has no node.
    public static let inspector = sections(curvature: true)

    /// The tangency weight is shown for Curvature (G2) only.
    public static func inspector(for node: Node) -> [InspectorSection] {
        if case .integer(1)? = node.inputValues["continuity"] { return sections(curvature: true) }
        return sections(curvature: false)
    }
    public static let handles = [HandleSpec.radial("radius")]
    public static let readsScrubbing = true

    /// Only a fillet that is (or may be, when `continuity` is wired) Curvature (G2) previews differently while a drag is in progress.
    public static func readsScrubbing(for node: Node) -> Bool {
        if case .integer(0)? = node.inputValues["continuity"] { return false }
        return true
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let set = try inputs.edgeSet("edges")
        let radius = try inputs.number("radius")
        // A drag previews the circular fillet (identical tags); the G2 surface is built when it ends.
        let profile: FilletProfile = try inputs.integer("continuity") == 1 && !context.isScrubbing
            ? .curvatureContinuous(weight: try inputs.number("tangency weight")) : .circular
        let made = try await kernel.fillet(set.solid, edges: set.edges, radius: radius, profile: profile, tag: context.tag)
        var outputs = NodeOutputs(["solid": .solid(made.solid)], warnings: warnings(for: made))
        outputs.dimensions = EdgeDimensions.fillet(set, radius: radius)
        return outputs
    }

    static func warnings(for made: FilletResult) -> [String] {
        var warnings: [String] = []
        if made.tangentOnlyCorners == 1 {
            warnings.append("1 fillet corner is tangent only (G1).")
        } else if made.tangentOnlyCorners > 1 {
            warnings.append("\(made.tangentOnlyCorners.display) fillet corners are tangent only (G1).")
        }
        if made.tangentOnlyJoins == 1 {
            warnings.append("1 fillet join is only approximately tangent where the edges kink.")
        } else if made.tangentOnlyJoins > 1 {
            warnings.append("\(made.tangentOnlyJoins.display) fillet joins are only approximately tangent where the edges kink.")
        }
        return warnings
    }
}
