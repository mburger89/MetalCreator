import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Turns placements into the moves that carry a tool built at the origin, facing +Z, onto them.
enum PlacementMoves {
    /// Refuses a tree on any input of a pattern node (User decision 8a): the node would run once per branch, cutting the
    /// part once for each and restarting `{i}` at 0 in each. Every node that places instances calls this first.
    static func requireFlat(_ context: EvalContext) throws {
        if context.isTreeRun {
            throw NodeError.invalidValue("Patterns take flat lists for now: flatten the tree first.")
        }
    }

    /// The move for each of `count` instances: instance `i` uses placement `i`, and a shorter list repeats its last
    /// placement (broadcasting, spec §4.2). A placement with no usable direction names its path.
    static func make(_ planes: [Plane], count: Int) throws -> [Transform] {
        guard let last = planes.indices.last else { return [] }
        var moves: [Transform] = []
        moves.reserveCapacity(count)
        for index in 0..<count {
            guard let move = planes[min(index, last)].placement else {
                throw NodeError.invalidValue("Placement \(InstancePath.text(index)) has no usable direction: "
                    + "its normal and x axis must not be zero or along each other.")
            }
            moves.append(move)
        }
        return moves
    }

    /// How a copy of a tool placed by node `place` names its faces (patterns spec §6): each of the tool's tag nodes
    /// `T` becomes `NodeID.instanceScoped([place, T])`. `place` is the identity the node evaluates under, so a node
    /// inside a group qualifies by its own instance.
    static func qualifier(placedBy place: NodeID) -> @Sendable (NodeID) -> NodeID {
        { NodeID.instanceScoped([place, $0]) }
    }
}
