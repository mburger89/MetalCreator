import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Turns placements into the moves that carry a tool built at the origin, facing +Z, onto them.
enum PlacementMoves {
    /// Refuses a tree on the part (or any other single-value input) of a shortcut node (User decision 8a): the node would
    /// run once per branch, cutting the part once for each. Only the placements and the sizes take trees
    /// (`InstanceGrid`), and they are read whole.
    static func requireSingleValues(_ context: EvalContext) throws {
        if context.isTreeRun {
            throw NodeError.invalidValue("Only placements and sizes can be trees: flatten the tree wired into the part "
                + "or the operation first.")
        }
    }

    /// The move for each instance, from the placement `planes[i]` of the instance whose tag item is `items[i]`. A
    /// placement with no usable direction names its path.
    static func make(_ planes: [Plane], items: [Int]) throws -> [Transform] {
        var moves: [Transform] = []
        moves.reserveCapacity(planes.count)
        for (plane, item) in zip(planes, items) {
            guard let move = plane.placement else {
                throw NodeError.invalidValue("Placement \(InstancePath.text(item)) has no usable direction: "
                    + "its normal and x axis must not be zero or along each other.")
            }
            moves.append(move)
        }
        return moves
    }

    /// Every copy of `tools[i]` on `planes[i]`, in one kernel call, named by `items[i]` (`InstancePath.item`): the
    /// kernel names each copy by its flat index, so a copy whose item is another number is renamed here, which changes
    /// no geometry and costs no kernel call.
    static func place(_ tools: [Solid], planes: [Plane], items: [Int], placedBy place: NodeID, kernel: any Kernel,
                      tag: NodeTag) async throws -> [Solid] {
        let moves = try make(planes, items: items)
        let copies = try await kernel.place(tools, at: moves, qualifying: qualifier(placedBy: place), tag: tag)
        return zip(copies, items).enumerated().map { index, pair in
            let (copy, item) = pair
            guard item != index else { return copy }
            return Solid(topology: copy.topology.withInstanceItem(item), bounds: copy.bounds, storage: copy.storage)
        }
    }

    /// How a copy of a tool placed by node `place` names its faces (patterns spec §6): each of the tool's tag nodes
    /// `T` becomes `NodeID.instanceScoped([place, T])`. `place` is the identity the node evaluates under, so a node
    /// inside a group qualifies by its own instance.
    static func qualifier(placedBy place: NodeID) -> @Sendable (NodeID) -> NodeID {
        { NodeID.instanceScoped([place, $0]) }
    }
}
