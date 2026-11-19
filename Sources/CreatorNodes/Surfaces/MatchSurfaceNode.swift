import CreatorGraph
import CreatorKernel

/// A sheet of one face changed along one edge to meet a target edge at G0, G1 or G2 (NURBS spec, NS-4, R9). The face keeps its names
/// and edges, so picks downstream survive. A G2 match built while a slider or handle is dragged is graded G1 and says nothing (R11);
/// the G2 build follows when the drag ends.
public enum MatchSurfaceNode: NodeDefinition {
    public static let typeID = "creator.matchSurface"
    public static let displayName = "Match Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    /// The choices of `continuity`, in option order.
    public static let continuityOptions = ["G0", "G1", "G2"]
    public static let inputs = [
        SocketSpec("edges", .edgeSet),
        SocketSpec("target", .edgeSet),
        SocketSpec("continuity", .integer, defaultValue: .integer(1)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    public static let inspector = [
        InspectorSection(title: "Match Surface", controls: [.segmented("continuity", options: continuityOptions)]),
        InspectorSection(title: "Edge", controls: [
            .ruleSummary("edges"), .button(title: "Pick edge in view…", action: .pickEdgesInView),
        ]),
        InspectorSection(title: "Target", controls: [
            .ruleSummary("target"), .button(title: "Pick target edge in view…", action: .pickTargetEdgesInView),
        ]),
    ]
    public static let readsScrubbing = true

    /// Only a match that is (or may be, when `continuity` is wired) G2 builds differently during a drag.
    public static func readsScrubbing(for node: Node) -> Bool {
        if case .integer(let grade)? = node.inputValues["continuity"] { return grade == 2 }
        return true
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let mine = try inputs.edgeSet("edges")
        guard mine.edges.count == 1 else {
            throw NodeError.invalidValue("Match Surface takes one edge to change; “edges” gives \(mine.edges.count.display).")
        }
        let theirs = try inputs.edgeSet("target")
        guard theirs.edges.count == 1 else {
            throw NodeError.invalidValue("Match Surface takes one target edge; “target” gives \(theirs.edges.count.display).")
        }
        let chosen = try inputs.choice("continuity", options: continuityOptions)
        let standIn = chosen == 2 && context.isScrubbing
        let continuity: PatchContinuity = chosen == 0 ? .g0 : (chosen == 1 || standIn ? .g1 : .g2)
        let result = try await kernel.matched(mine.solid, edge: mine.edges[0], to: theirs.edges[0], of: theirs.solid,
                                              continuity: continuity)
        // R11: G0 and G1 always ask (their cache key has no scrubbing flag); the G2 stand-in leaves it to the build after the drag.
        var warnings: [String] = []
        if !standIn, try await kernel.folds(result) { warnings.append(EditSurfaceNode.foldWarning) }
        return NodeOutputs(["surface": .solid(result)], warnings: warnings)
    }
}
