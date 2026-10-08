import CreatorGraph
import CreatorKernel

/// The rule that picking writes (spec §5.3, rule 5): edges named by remembered `EdgePick`s,
/// stored in the `picks` setting as `.edgePicks(solid.topology.picks(for: edgeIDs))`; the M6 app
/// shell writes it from viewport picks. A key matches by tag subsets on each side, so unions that
/// merge faces keep the pick. A changed match count is a warning, never silent (rule 6).
public enum EdgesByTagNode: NodeDefinition {
    public static let typeID = "creator.edgesByTag"
    public static let displayName = "Edges by Tag"
    public static let category = NodeCategory.selection
    public static let inputs = [SocketSpec("solid", .solid)]
    public static let outputs = [SocketSpec("edges", .edgeSet)]
    public static let inspector = [InspectorSection(title: "Edges", controls: [
        .ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView),
    ])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let picks: [EdgePick]
        switch context.node.inputValues[NodeSetting.picks] {
        case nil: picks = []
        case .edgePicks(let stored)?: picks = stored
        case .some: throw NodeError.invalidValue("This rule's picked edges can't be read. Pick the edges again.")
        }
        let match = EdgeTagMatch.resolve(picks, in: solid.topology)
        return EdgeSelection.outputs(solid, match.edges, warnings: match.warnings)
    }
}
