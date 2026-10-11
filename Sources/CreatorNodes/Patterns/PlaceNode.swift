import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A copy of a tool for every placement (patterns spec §3): the tool is built at the origin facing +Z, and each
/// placement is a plane that says where a copy goes and which way it faces. One kernel call places every copy
/// (`Kernel.place`), and copies of one tool share its geometry. A copy's face tags are its tool's, qualified by the
/// copy's index (`NodeID.instanceScoped`, §6), so a pick on one copy follows it through edits to the pattern.
///
/// Tools and placements broadcast: the longer list sets the number of copies and the shorter repeats its last item.
/// Wire the copies into a Boolean's `tools` to cut or join them all at once.
public enum PlaceNode: NodeDefinition {
    public static let typeID = "creator.place"
    public static let displayName = "Place"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let inputs = [
        SocketSpec("tool", .solid, access: .list),
        SocketSpec("placements", .plane, access: .list),
    ]
    public static let outputs = [SocketSpec("solids", .solid)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try PlacementMoves.requireFlat(context)
        let tools = try inputs.solids("tool")
        let planes = try inputs.planes("placements")
        let count = tools.isEmpty || planes.isEmpty ? 0 : max(tools.count, planes.count)
        try PatternLimit.check(count)
        let moves = try PlacementMoves.make(planes, count: count)
        let used = (0..<count).map { tools[min($0, tools.count - 1)] }
        let copies = try await kernel.place(used, at: moves, qualifying: PlacementMoves.qualifier(placedBy: context.node.id),
                                            tag: context.tag)
        return NodeOutputs(lists: ["solids": copies.map(Scalar.solid)])
    }
}
