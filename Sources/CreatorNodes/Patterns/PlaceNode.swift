import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A copy of a tool for every placement (patterns spec §3): the tool is built at the origin facing +Z, and each
/// placement is a plane that says where a copy goes and which way it faces. One kernel call places every copy
/// (`Kernel.place`), and copies of one tool share its geometry. A copy's face tags are its tool's, qualified by the
/// copy's path (`NodeID.instanceScoped`, §6): `{i}` in a flat list, `{row;i}` in a tree, so a pick on one copy follows
/// it through edits to the pattern.
///
/// An implicit solid is placed the same way (implicit spec §3.3): wire it into `implicit` and each copy is the solid seen through the
/// placement's rigid move, exact, one node per placement, on `implicits`. `tool` and `implicit` may both be wired; at least one must be.
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
        SocketSpec("tool", .solid, access: .tree, optional: true),
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("implicit", .implicit, access: .tree, optional: true),
    ]
    public static let outputs = [SocketSpec("solids", .solid, optional: true), SocketSpec("implicits", .implicit, optional: true)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard inputs.has("tool") || inputs.has("implicit") else { throw NodeError.missingInput("tool") }
        var trees: [SocketName: DataTree] = [:]
        if inputs.has("tool") {
            let grid = try InstanceGrid(inputs, ["placements", "tool"])
            if grid.count > 0 {
                let copies = try await PlacementMoves.place(try grid.solids("tool"), planes: try grid.planes("placements"),
                                                            items: grid.items, placedBy: context.node.id, kernel: kernel, tag: context.tag)
                trees["solids"] = grid.tree(of: copies.map(Scalar.solid))
            } else {
                trees["solids"] = grid.tree(of: [])
            }
        }
        if inputs.has("implicit") { trees["implicits"] = try placedImplicits(inputs) }
        return NodeOutputs(trees: trees)
    }

    /// The implicit solid for each placement, moved onto it (implicit spec §3.3): a rigid transform, so the distance stays exact.
    private static func placedImplicits(_ inputs: NodeInputs) throws -> DataTree {
        let grid = try InstanceGrid(inputs, ["placements", "implicit"])
        guard grid.count > 0 else { return grid.tree(of: []) }
        let planes = try grid.planes("placements")
        let shapes = try grid.implicits("implicit")
        var copies: [Scalar] = []
        for (index, (plane, shape)) in zip(planes, shapes).enumerated() {
            guard let move = RigidMove(plane: plane) else {
                throw NodeError.invalidValue("Placement \(InstancePath.text(grid.items[index])) has no usable direction: "
                    + "its normal and x axis must not be zero or along each other.")
            }
            guard let solid = shape.solid else { throw NodeError.typeMismatch("implicit", expected: .implicit) }
            copies.append(.implicit(ImplicitSolid.moved(solid, move).reference))
        }
        return grid.tree(of: copies)
    }
}
