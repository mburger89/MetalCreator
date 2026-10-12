import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A copy of a tool for every placement (patterns spec §3): the tool is built at the origin facing +Z, and each
/// placement is a plane that says where a copy goes and which way it faces. One kernel call places every copy
/// (`Kernel.place`), and copies of one tool share its geometry. A copy's face tags are its tool's, qualified by the
/// copy's path (`NodeID.instanceScoped`, §6): `{i}` in a flat list, `{row;i}` in a tree, so a pick on one copy follows
/// it through edits to the pattern.
///
/// Tools and placements are matched as `InstanceGrid` says: the longer flat list sets the number of copies and the
/// shorter repeats its last item; a tree of placements (a Grid Pattern's rows, a Circular Pattern's rings) comes out
/// as a tree of copies of the same shape, and a flat tool applies to every branch. Wire the copies into a Boolean's
/// `tools` to cut or join them all at once (it takes one branch of a tree at a time; Flatten them first to use one).
public enum PlaceNode: NodeDefinition {
    public static let typeID = "creator.place"
    public static let displayName = "Place"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let inputs = [
        SocketSpec("tool", .solid, access: .tree),
        SocketSpec("placements", .plane, access: .tree),
    ]
    public static let outputs = [SocketSpec("solids", .solid)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let grid = try InstanceGrid(inputs, ["placements", "tool"])
        guard grid.count > 0 else { return NodeOutputs(trees: ["solids": grid.tree(of: [])]) }
        let copies = try await PlacementMoves.place(try grid.solids("tool"), planes: try grid.planes("placements"), items: grid.items,
                                                    placedBy: context.node.id, kernel: kernel, tag: context.tag)
        return NodeOutputs(trees: ["solids": grid.tree(of: copies.map(Scalar.solid))])
    }
}
